#!/usr/bin/env python3
"""
Retarget Mixamo FBX animations onto the Cartoon Cat model.

Usage:
  # Retarget + inject (both steps):
  python3 retarget_mixamo.py walk.fbx Cat_Walk run.fbx Cat_Run

  # Just inject previously exported gltfs:
  python3 retarget_mixamo.py --inject-only

Requirements:
  - Blender 5.0+ at ../../apps/blender/blender (or set BLENDER env var)
  - cartoon_cat.gltf.bak as the clean original (created on first run)

The script:
  1. Runs Blender headlessly to retarget each FBX onto the cat skeleton
  2. Exports each as a temporary gltf (Blender handles coordinate conversion)
  3. Injects all animation data into cartoon_cat.gltf
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLENDER = os.environ.get("BLENDER", os.path.join(SCRIPT_DIR, "..", "..", "apps", "blender", "blender"))
ORIG_GLTF = os.path.join(SCRIPT_DIR, "cartoon_cat.gltf")
ORIG_BIN = os.path.join(SCRIPT_DIR, "cartoon_cat.bin")
BAK_GLTF = ORIG_GLTF + ".bak"
BAK_BIN = ORIG_BIN + ".bak"

# Mixamo -> Cartoon Cat bone mapping
# Excludes Hips (causes 90-deg turn), Hands (different wrist), Shoulders (squishes torso)
BONE_MAP = {
    "mixamorig:Spine": "Bone1_01",
    "mixamorig:Spine1": "Bone2_02",
    "mixamorig:Spine2": "Bone3_03",
    "mixamorig:Neck": "Neack_04",
    "mixamorig:Head": "Head_05",
    "mixamorig:LeftArm": "Arm1_R_034",
    "mixamorig:LeftForeArm": "Arm2_R_035",
    "mixamorig:RightArm": "Arm1_L_025",
    "mixamorig:RightForeArm": "Arm2_L_026",
    "mixamorig:LeftUpLeg": "Leg_Up_L_045",
    "mixamorig:LeftLeg": "Leg_Dwn_L_046",
    "mixamorig:LeftFoot": "Foot_L_047",
    "mixamorig:LeftToeBase": "Foot_Dwn_L_048",
    "mixamorig:RightUpLeg": "Leg_Up_R_049",
    "mixamorig:RightLeg": "Leg_Dwn_R_050",
    "mixamorig:RightFoot": "Foot_R_051",
    "mixamorig:RightToeBase": "Foot_Dwn_R_052",
}


def generate_blender_script(cat_gltf, fbx_path, anim_name, output_gltf):
    """Generate a Blender Python script for retargeting one animation."""
    bone_map_str = repr(BONE_MAP)
    return f'''
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)

BONE_MAP = {bone_map_str}

# Import cat
bpy.ops.import_scene.gltf(filepath="{cat_gltf}")
cat_arm = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        cat_arm = obj
        break

# Import Mixamo FBX
bpy.ops.import_scene.fbx(filepath="{fbx_path}")
mix_arm = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE' and obj != cat_arm:
        mix_arm = obj
        break

mix_action = mix_arm.animation_data.action
frame_start = int(mix_action.frame_range[0])
frame_end = int(mix_action.frame_range[1])
print(f"Frames: {{frame_start}}-{{frame_end}}")

# Set up WORLD-space Copy Rotation constraints
bpy.context.view_layer.objects.active = cat_arm
bpy.ops.object.mode_set(mode='POSE')
for mix_bone, cat_bone in BONE_MAP.items():
    clean_mix = mix_bone.replace(":", "_")
    actual_mix = None
    for b in mix_arm.pose.bones:
        if b.name == mix_bone or b.name == clean_mix:
            actual_mix = b.name
            break
    if not actual_mix or cat_bone not in cat_arm.pose.bones:
        continue
    pb = cat_arm.pose.bones[cat_bone]
    for c in pb.constraints:
        pb.constraints.remove(c)
    cr = pb.constraints.new('COPY_ROTATION')
    cr.target = mix_arm
    cr.subtarget = actual_mix
    cr.owner_space = 'WORLD'
    cr.target_space = 'WORLD'
    cr.mix_mode = 'REPLACE'
bpy.ops.object.mode_set(mode='OBJECT')

# Bake
bpy.context.scene.frame_start = frame_start
bpy.context.scene.frame_end = frame_end
bpy.context.view_layer.objects.active = cat_arm
cat_arm.select_set(True)
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.select_all(action='SELECT')
bpy.ops.nla.bake(
    frame_start=frame_start, frame_end=frame_end,
    only_selected=False, visual_keying=True,
    clear_constraints=True, use_current_action=False,
    bake_types={{'POSE'}},
)
bpy.ops.object.mode_set(mode='OBJECT')

if cat_arm.animation_data and cat_arm.animation_data.action:
    cat_arm.animation_data.action.name = "{anim_name}"

# Remove non-cat objects
for obj in list(bpy.data.objects):
    if obj == cat_arm:
        continue
    is_cat = False
    p = obj
    while p:
        if p == cat_arm:
            is_cat = True
            break
        p = p.parent
    if not is_cat:
        bpy.data.objects.remove(obj, do_unlink=True)

bpy.ops.export_scene.gltf(
    filepath="{output_gltf}",
    export_format='GLTF_SEPARATE',
    use_selection=False,
    export_animations=True,
    export_skins=True,
    export_yup=True,
)
print("RETARGET_OK")
'''


def retarget_fbx(fbx_path, anim_name, tmp_dir):
    """Run Blender to retarget one FBX. Returns path to exported gltf."""
    output_gltf = os.path.join(tmp_dir, f"{anim_name}.gltf")
    script = generate_blender_script(BAK_GLTF, fbx_path, anim_name, output_gltf)
    script_path = os.path.join(tmp_dir, f"retarget_{anim_name}.py")
    with open(script_path, "w") as f:
        f.write(script)

    print(f"  Retargeting {anim_name} from {os.path.basename(fbx_path)}...")
    result = subprocess.run(
        [BLENDER, "--background", "--python", script_path],
        capture_output=True, text=True, timeout=300
    )
    if "RETARGET_OK" not in result.stdout:
        print(f"  ERROR: Blender retarget failed for {anim_name}")
        print(result.stdout[-500:] if result.stdout else "")
        print(result.stderr[-500:] if result.stderr else "")
        return None
    print(f"  OK: {anim_name}")
    return output_gltf


def inject_animations(anim_gltfs):
    """Inject animations from exported gltfs into the original cartoon_cat.gltf."""
    # Restore from backup
    shutil.copy2(BAK_GLTF, ORIG_GLTF)
    shutil.copy2(BAK_BIN, ORIG_BIN)

    with open(ORIG_GLTF) as f:
        orig = json.load(f)
    with open(ORIG_BIN, "rb") as f:
        orig_bin = bytearray(f.read())

    orig_node_map = {}
    for i, node in enumerate(orig["nodes"]):
        if "name" in node:
            orig_node_map[node["name"]] = i

    # Build valid channels from original animations
    valid_channels = set()
    for anim in orig["animations"]:
        for ch in anim["channels"]:
            node_name = orig["nodes"][ch["target"]["node"]].get("name", "")
            valid_channels.add((node_name, ch["target"]["path"]))

    print(f"Original: {len(orig['animations'])} animations")

    for gltf_path, bin_path, anim_name in anim_gltfs:
        if not os.path.exists(gltf_path):
            print(f"  SKIP: {gltf_path} not found")
            continue
        with open(gltf_path) as f:
            walk = json.load(f)
        with open(bin_path, "rb") as f:
            walk_bin = bytearray(f.read())

        walk_idx_to_name = {i: n.get("name", "") for i, n in enumerate(walk["nodes"])}

        walk_anim = None
        for a in walk["animations"]:
            if a["name"] == anim_name:
                walk_anim = a
                break
        if not walk_anim:
            print(f"  SKIP: {anim_name} not found in gltf")
            continue

        # Find kept channels
        kept_sampler_indices = set()
        kept_channels = []
        for ch in walk_anim["channels"]:
            node_name = walk_idx_to_name.get(ch["target"]["node"])
            path = ch["target"]["path"]
            if node_name not in orig_node_map:
                continue
            if (node_name, path) not in valid_channels:
                continue
            kept_sampler_indices.add(ch["sampler"])
            kept_channels.append(ch)

        # Copy accessor data
        used_accessors = set()
        for si in kept_sampler_indices:
            s = walk_anim["samplers"][si]
            used_accessors.add(s["input"])
            used_accessors.add(s["output"])

        accessor_map = {}
        for old_idx in sorted(used_accessors):
            acc = walk["accessors"][old_idx]
            bv = walk["bufferViews"][acc["bufferView"]]
            data = walk_bin[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
            while len(orig_bin) % 4 != 0:
                orig_bin.append(0)
            new_offset = len(orig_bin)
            orig_bin.extend(data)
            new_bv = {"buffer": 0, "byteOffset": new_offset, "byteLength": bv["byteLength"]}
            if "byteStride" in bv:
                new_bv["byteStride"] = bv["byteStride"]
            orig["bufferViews"].append(new_bv)
            new_acc = {"bufferView": len(orig["bufferViews"]) - 1,
                       "componentType": acc["componentType"], "count": acc["count"], "type": acc["type"]}
            for k in ("byteOffset", "max", "min"):
                if k in acc:
                    new_acc[k] = acc[k]
            orig["accessors"].append(new_acc)
            accessor_map[old_idx] = len(orig["accessors"]) - 1

        sampler_map = {}
        new_samplers = []
        for old_idx in sorted(kept_sampler_indices):
            s = walk_anim["samplers"][old_idx]
            ns = {"input": accessor_map[s["input"]], "output": accessor_map[s["output"]]}
            if "interpolation" in s:
                ns["interpolation"] = s["interpolation"]
            sampler_map[old_idx] = len(new_samplers)
            new_samplers.append(ns)

        new_channels = []
        for ch in kept_channels:
            node_name = walk_idx_to_name.get(ch["target"]["node"])
            new_channels.append({
                "sampler": sampler_map[ch["sampler"]],
                "target": {"node": orig_node_map[node_name], "path": ch["target"]["path"]}
            })

        orig["animations"].append({"name": anim_name, "channels": new_channels, "samplers": new_samplers})
        print(f"  {anim_name}: {len(new_channels)} channels")

    orig["buffers"][0]["byteLength"] = len(orig_bin)
    with open(ORIG_GLTF, "w") as f:
        json.dump(orig, f)
    with open(ORIG_BIN, "wb") as f:
        f.write(orig_bin)
    print(f"Final: {len(orig['animations'])} animations, {len(orig_bin)} bytes")


def main():
    # Ensure backup exists
    if not os.path.exists(BAK_GLTF):
        shutil.copy2(ORIG_GLTF, BAK_GLTF)
        shutil.copy2(ORIG_BIN, BAK_BIN)
        print("Created backup of original gltf/bin")

    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return

    # Parse pairs: fbx_path anim_name fbx_path anim_name ...
    pairs = []
    i = 0
    while i < len(args):
        if args[i] == "--inject-only":
            i += 1
            continue
        fbx = args[i]
        if not os.path.exists(fbx):
            print(f"ERROR: {fbx} not found")
            sys.exit(1)
        if i + 1 >= len(args):
            print(f"ERROR: missing animation name for {fbx}")
            sys.exit(1)
        name = args[i + 1]
        pairs.append((fbx, name))
        i += 2

    if not pairs:
        print("No FBX files specified")
        return

    with tempfile.TemporaryDirectory() as tmp_dir:
        anim_gltfs = []
        for fbx, name in pairs:
            gltf_path = retarget_fbx(os.path.abspath(fbx), name, tmp_dir)
            if gltf_path:
                bin_path = gltf_path.replace(".gltf", ".bin")
                anim_gltfs.append((gltf_path, bin_path, name))

        if anim_gltfs:
            inject_animations(anim_gltfs)
            print("\nDone! Clear Godot import cache and reimport:")
            print("  rm -f .godot/imported/cartoon_cat* cartoon_cat.gltf.import")
            print("  godot --headless --editor --quit-after 30")


if __name__ == "__main__":
    main()
