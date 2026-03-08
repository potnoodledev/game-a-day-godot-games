#!/usr/bin/env python3
"""
Sketchfab hat tool — search, download, normalize, and prepare hats for the cat viewer.

Usage:
  # First time: get your API token from Sketchfab
  #   1. Log in to sketchfab.com
  #   2. Go to Settings → Password & API → API Token
  #   3. Save it to .env:
  echo "SKETCHFAB_API_KEY=your_token" >> .env

  # Search for hats:
  python3 sketchfab_hat_tool.py search "top hat cartoon"
  python3 sketchfab_hat_tool.py search "witch hat low poly" --limit 20

  # Download and normalize a hat (by Sketchfab UID):
  python3 sketchfab_hat_tool.py download <uid> --name "top_hat"

  # List downloaded hats:
  python3 sketchfab_hat_tool.py list

  # Adjust hat offset/scale in hat_registry.json, then rebuild
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import urllib.error
import zipfile

API_BASE = "https://api.sketchfab.com/v3"
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
HATS_DIR = os.path.join(PROJECT_DIR, "hats")
REGISTRY_FILE = os.path.join(HATS_DIR, "hat_registry.json")
ENV_FILE = os.path.join(PROJECT_DIR, ".env")
BLENDER = os.path.expanduser("~/projects/game-a-day/apps/blender/blender")

# Target hat size in Blender units.
# The cat is scaled 0.25x in Godot; head is roughly 0.8 units in model space.
# We scale so the largest dimension (width or height) fits TARGET_MAX_DIM.
TARGET_MAX_DIM = 0.4
MAX_FACES = 2000       # Decimate meshes above this threshold
MAX_TEX_SIZE = 128     # Texture resolution cap (128x128 is plenty for hats)
STRIP_PBR = True       # Remove normal/metallic/roughness maps for smaller GLBs


def get_token():
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("SKETCHFAB_API_KEY="):
                    token = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if token:
                        return token
    print("No Sketchfab API key found.")
    print("  1. Log in to https://sketchfab.com")
    print("  2. Settings → Password & API → API Token")
    print("  3. Add to .env: SKETCHFAB_API_KEY=your_token")
    sys.exit(1)


def api_get(path, token=None):
    url = f"{API_BASE}/{path}" if not path.startswith("http") else path
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Token {token}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:200]
        print(f"HTTP {e.code}: {body}")
        raise


def load_registry():
    if os.path.exists(REGISTRY_FILE):
        with open(REGISTRY_FILE) as f:
            return json.load(f)
    return {}


def save_registry(registry):
    with open(REGISTRY_FILE, "w") as f:
        json.dump(registry, f, indent=2)


def cmd_search(args):
    query = " ".join(args.query)
    params = urllib.parse.urlencode({
        "q": query,
        "downloadable": "true",
        "type": "models",
        "count": args.limit,
        "sort_by": "-likeCount",
    })
    data = api_get(f"search?{params}")
    results = data.get("results", [])
    if not results:
        print(f"No results for '{query}'")
        return

    print(f"\n{'UID':<35} {'Name':<30} {'Faces':<10} {'License'}")
    print("-" * 90)
    for r in results:
        uid = r["uid"]
        name = r["name"][:29]
        faces = r.get("faceCount", "?")
        if isinstance(faces, int):
            faces = f"{faces:,}"
        license_info = r.get("license", {})
        license_label = license_info.get("label", "?") if license_info else "?"
        print(f"{uid:<35} {name:<30} {faces:<10} {license_label}")
    print(f"\nTo download: python3 sketchfab_hat_tool.py download <UID> --name hat_name")


def cmd_download(args):
    token = get_token()
    uid = args.uid
    hat_name = args.name or uid[:12]
    hat_name = hat_name.replace(" ", "_").replace("-", "_").lower()

    os.makedirs(HATS_DIR, exist_ok=True)
    output_glb = os.path.join(HATS_DIR, f"{hat_name}.glb")

    if os.path.exists(output_glb) and not args.force:
        print(f"  Already exists: {hat_name}.glb (use --force to re-download)")
        return

    # Get model info
    print(f"  Fetching model info for {uid}...")
    model_info = api_get(f"models/{uid}", token)
    model_name = model_info.get("name", uid)
    author = model_info.get("user", {}).get("displayName", "unknown")
    license_info = model_info.get("license", {})
    license_label = license_info.get("label", "unknown") if license_info else "unknown"

    # Get download URL
    print(f"  Requesting download for: {model_name}")
    try:
        dl_info = api_get(f"models/{uid}/download", token)
    except urllib.error.HTTPError as e:
        if e.code == 403:
            print(f"  ERROR: Model not downloadable or requires purchase")
            return
        raise

    gltf_dl = dl_info.get("gltf", {})
    dl_url = gltf_dl.get("url")
    if not dl_url:
        print(f"  ERROR: No GLTF download available")
        return

    # Download ZIP
    print(f"  Downloading ({gltf_dl.get('size', '?')} bytes)...")
    with tempfile.TemporaryDirectory() as tmp_dir:
        zip_path = os.path.join(tmp_dir, "model.zip")
        req = urllib.request.Request(dl_url)
        with urllib.request.urlopen(req, timeout=120) as resp:
            with open(zip_path, "wb") as f:
                f.write(resp.read())

        # Extract
        extract_dir = os.path.join(tmp_dir, "extracted")
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract_dir)

        # Find the GLTF/GLB file
        model_file = None
        for root, dirs, files in os.walk(extract_dir):
            for fname in files:
                if fname.endswith((".gltf", ".glb")):
                    model_file = os.path.join(root, fname)
                    break
            if model_file:
                break

        if not model_file:
            print(f"  ERROR: No GLTF/GLB file found in download")
            return

        print(f"  Found: {os.path.basename(model_file)}")

        # Normalize with Blender
        print(f"  Normalizing with Blender...")
        _normalize_hat(model_file, output_glb, tmp_dir)

    if not os.path.exists(output_glb):
        print(f"  ERROR: Blender normalization failed")
        return

    print(f"  OK: {hat_name}.glb")

    # Update registry
    registry = load_registry()
    registry[hat_name] = {
        "file": f"{hat_name}.glb",
        "display_name": model_name[:30],
        "offset": [0.0, 0.35, 0.0],
        "rotation": [0.0, 0.0, 0.0],
        "scale": [1.0, 1.0, 1.0],
        "source_uid": uid,
        "license": license_label,
        "author": author,
    }
    save_registry(registry)
    print(f"  Registry updated. Adjust offset/rotation/scale in hat_registry.json if needed.")


def _normalize_hat(input_file, output_glb, tmp_dir):
    """Run Blender to normalize hat: center, orient front along -Y, uniform scale,
    decimate, compress textures, strip PBR maps, export as GLB."""

    script = f'''
import bpy
import mathutils

bpy.ops.wm.read_factory_settings(use_empty=True)

# Import model
bpy.ops.import_scene.gltf(filepath="{input_file}")

# Remove non-mesh objects (armatures, cameras, lights, empties)
to_remove = [obj for obj in bpy.data.objects if obj.type not in ('MESH',)]
for obj in to_remove:
    bpy.data.objects.remove(obj, do_unlink=True)

meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH']
if not meshes:
    print("NORMALIZE_FAIL: No meshes found")
    raise SystemExit(1)

# Select all meshes and join
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()

obj = bpy.context.active_object

# Apply all transforms
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Center origin to bottom-center of bounding box ---
bbox = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
min_z = min(v.z for v in bbox)
center_x = sum(v.x for v in bbox) / 8
center_y = sum(v.y for v in bbox) / 8
offset = mathutils.Vector((-center_x, -center_y, -min_z))
obj.data.transform(mathutils.Matrix.Translation(offset))
obj.location = (0, 0, 0)

# --- Scale to fit TARGET_MAX_DIM on the largest axis ---
bbox2 = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
size_x = max(v.x for v in bbox2) - min(v.x for v in bbox2)
size_y = max(v.y for v in bbox2) - min(v.y for v in bbox2)
size_z = max(v.z for v in bbox2) - min(v.z for v in bbox2)
max_dim = max(size_x, size_y, size_z)
if max_dim > 0:
    scale_factor = {TARGET_MAX_DIM} / max_dim
    obj.scale = (scale_factor, scale_factor, scale_factor)
    bpy.ops.object.transform_apply(scale=True)
print(f"  Dims before scale: {{size_x:.3f}} x {{size_y:.3f}} x {{size_z:.3f}}, max={{max_dim:.3f}}")

# --- Decimate if too many faces ---
face_count = len(obj.data.polygons)
if face_count > {MAX_FACES}:
    ratio = {MAX_FACES} / face_count
    mod = obj.modifiers.new("Decimate", 'DECIMATE')
    mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier="Decimate")
    new_count = len(obj.data.polygons)
    print(f"  Decimated: {{face_count}} -> {{new_count}} faces")
else:
    print(f"  Faces: {{face_count}} (OK)")

# --- Strip PBR maps (normal, metallic/roughness) for smaller GLBs ---
strip_pbr = {STRIP_PBR}
if strip_pbr:
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        bsdf = None
        for node in mat.node_tree.nodes:
            if node.type == 'BSDF_PRINCIPLED':
                bsdf = node
                break
        if not bsdf:
            continue
        # Disconnect normal map
        normal_input = bsdf.inputs.get("Normal")
        if normal_input and normal_input.is_linked:
            for link in normal_input.links:
                mat.node_tree.links.remove(link)
        # Set metallic to 0, roughness to 0.8 (stylized look)
        metallic_input = bsdf.inputs.get("Metallic")
        if metallic_input:
            if metallic_input.is_linked:
                for link in metallic_input.links:
                    mat.node_tree.links.remove(link)
            metallic_input.default_value = 0.0
        roughness_input = bsdf.inputs.get("Roughness")
        if roughness_input:
            if roughness_input.is_linked:
                for link in roughness_input.links:
                    mat.node_tree.links.remove(link)
            roughness_input.default_value = 0.8
    # Remove orphan images that are no longer connected
    # (they won't be exported since nothing references them)
    print("  Stripped PBR maps (normal/metallic/roughness)")

# --- Resize remaining textures ---
MAX_TEX = {MAX_TEX_SIZE}
for img in bpy.data.images:
    if img.size[0] > MAX_TEX or img.size[1] > MAX_TEX:
        ratio = min(MAX_TEX / img.size[0], MAX_TEX / img.size[1])
        new_w = max(1, int(img.size[0] * ratio))
        new_h = max(1, int(img.size[1] * ratio))
        img.scale(new_w, new_h)
        print(f"  Resized texture {{img.name}} to {{new_w}}x{{new_h}}")

# Export as GLB
bpy.ops.export_scene.gltf(
    filepath="{output_glb}",
    export_format='GLB',
    use_selection=True,
    export_animations=False,
    export_skins=False,
    export_yup=True,
)

# Report final size
import os
size_kb = os.path.getsize("{output_glb}") / 1024
print(f"  Output: {{size_kb:.0f}} KB")
print("NORMALIZE_OK")
'''
    script_path = os.path.join(tmp_dir, "normalize_hat.py")
    with open(script_path, "w") as f:
        f.write(script)

    result = subprocess.run(
        [BLENDER, "--background", "--python", script_path],
        capture_output=True, text=True, timeout=120
    )
    if "NORMALIZE_OK" not in result.stdout:
        print(f"  Blender output: {result.stdout[-500:]}")
        if result.stderr:
            for line in result.stderr.split("\n"):
                if "Error" in line or "ERROR" in line:
                    print(f"  {line}")
    else:
        # Print normalize info lines
        for line in result.stdout.split("\n"):
            if line.strip().startswith("  "):
                print(line)


def cmd_list(args):
    registry = load_registry()
    if not registry:
        print("No hats downloaded yet")
        return

    print(f"\n{'ID':<20} {'Name':<25} {'Author':<20} {'License'}")
    print("-" * 75)
    for hat_id, info in sorted(registry.items()):
        glb_path = os.path.join(HATS_DIR, info["file"])
        exists = "OK" if os.path.exists(glb_path) else "MISSING"
        print(f"{hat_id:<20} {info['display_name']:<25} {info['author']:<20} {info['license']}")
    print(f"\n{len(registry)} hats in registry")


def cmd_adjust(args):
    """Interactive offset/scale adjustment helper."""
    registry = load_registry()
    hat_id = args.hat_id
    if hat_id not in registry:
        print(f"Unknown hat: {hat_id}")
        print(f"Available: {', '.join(registry.keys())}")
        return

    info = registry[hat_id]
    if args.offset:
        info["offset"] = [float(x) for x in args.offset.split(",")]
    if args.rotation:
        info["rotation"] = [float(x) for x in args.rotation.split(",")]
    if args.scale:
        vals = [float(x) for x in args.scale.split(",")]
        if len(vals) == 1:
            vals = vals * 3
        info["scale"] = vals

    save_registry(registry)
    print(f"Updated {hat_id}:")
    print(f"  offset:   {info['offset']}")
    print(f"  rotation: {info['rotation']}")
    print(f"  scale:    {info['scale']}")


def cmd_renormalize(args):
    """Re-run normalization on all existing hats (or a specific one)."""
    registry = load_registry()
    if not registry:
        print("No hats in registry")
        return

    targets = [args.hat_id] if args.hat_id else sorted(registry.keys())
    for hat_id in targets:
        if hat_id not in registry:
            print(f"Unknown hat: {hat_id}")
            continue
        info = registry[hat_id]
        uid = info.get("source_uid")
        if not uid:
            print(f"  {hat_id}: no source_uid, skipping")
            continue

        glb_path = os.path.join(HATS_DIR, info["file"])
        if not os.path.exists(glb_path):
            print(f"  {hat_id}: GLB missing, skipping")
            continue

        print(f"\n  Renormalizing {hat_id}...")
        with tempfile.TemporaryDirectory() as tmp_dir:
            _normalize_hat(glb_path, glb_path, tmp_dir)

        # Reset offset/rotation/scale to defaults since the hat is now properly oriented
        info["offset"] = [0.0, 0.08, 0.0]
        info["rotation"] = [0.0, 0.0, 0.0]
        info["scale"] = [1.0, 1.0, 1.0]

    save_registry(registry)
    print(f"\nDone. Re-import in Godot:")
    print(f"  rm -f .godot/imported/*hat*")
    print(f"  godot --headless --editor --quit-after 10")


def cmd_inspect(args):
    """Show dimensions and stats for all hats (via Blender)."""
    import json as _json
    hats = sorted(f for f in os.listdir(HATS_DIR) if f.endswith(".glb"))
    if not hats:
        print("No hat GLBs found")
        return

    script = '''
import bpy, json, os, mathutils
hats_dir = "HATS_DIR_PLACEHOLDER"
results = {}
for f in sorted(os.listdir(hats_dir)):
    if not f.endswith(".glb"): continue
    name = f.replace(".glb","")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(hats_dir, f))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes: continue
    all_verts = []
    for obj in meshes:
        for v in obj.data.vertices:
            all_verts.append(obj.matrix_world @ v.co)
    xs = [v.x for v in all_verts]
    ys = [v.y for v in all_verts]
    zs = [v.z for v in all_verts]
    faces = sum(len(o.data.polygons) for o in meshes)
    verts = sum(len(o.data.vertices) for o in meshes)
    file_kb = os.path.getsize(os.path.join(hats_dir, f)) / 1024
    results[name] = {
        "w": round(max(xs)-min(xs),3), "d": round(max(ys)-min(ys),3), "h": round(max(zs)-min(zs),3),
        "faces": faces, "verts": verts, "kb": round(file_kb,1),
    }
print("INSPECT:" + json.dumps(results))
'''.replace("HATS_DIR_PLACEHOLDER", HATS_DIR)

    with tempfile.TemporaryDirectory() as tmp_dir:
        script_path = os.path.join(tmp_dir, "inspect.py")
        with open(script_path, "w") as f:
            f.write(script)
        result = subprocess.run(
            [BLENDER, "--background", "--python", script_path],
            capture_output=True, text=True, timeout=120
        )

    for line in result.stdout.split("\n"):
        if line.startswith("INSPECT:"):
            data = _json.loads(line[8:])
            print(f"\n{'Hat':<20} {'W':>6} {'D':>6} {'H':>6} {'Faces':>7} {'Verts':>7} {'Size':>8}")
            print("-" * 68)
            for name, info in sorted(data.items()):
                print(f"{name:<20} {info['w']:>6.3f} {info['d']:>6.3f} {info['h']:>6.3f} {info['faces']:>7} {info['verts']:>7} {info['kb']:>6.1f}KB")
            return
    print("Blender inspection failed")


def main():
    parser = argparse.ArgumentParser(
        description="Sketchfab hat tool — search, download, normalize",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")

    p_search = sub.add_parser("search", help="Search Sketchfab for hat models")
    p_search.add_argument("query", nargs="+", help="Search terms")
    p_search.add_argument("--limit", type=int, default=10, help="Max results")

    p_dl = sub.add_parser("download", help="Download and normalize a hat")
    p_dl.add_argument("uid", help="Sketchfab model UID")
    p_dl.add_argument("--name", help="Hat ID name (e.g. top_hat)")
    p_dl.add_argument("--force", action="store_true", help="Re-download even if exists")

    p_list = sub.add_parser("list", help="List downloaded hats")

    p_adj = sub.add_parser("adjust", help="Adjust hat offset/rotation/scale")
    p_adj.add_argument("hat_id", help="Hat ID from registry")
    p_adj.add_argument("--offset", help="x,y,z offset (e.g. 0,0.1,0)")
    p_adj.add_argument("--rotation", help="x,y,z rotation degrees (e.g. 0,90,0)")
    p_adj.add_argument("--scale", help="x,y,z scale or uniform (e.g. 1.5)")

    p_renorm = sub.add_parser("renormalize", help="Re-normalize all hats (or one)")
    p_renorm.add_argument("hat_id", nargs="?", help="Specific hat ID (default: all)")

    p_inspect = sub.add_parser("inspect", help="Show hat dimensions and stats")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return

    {"search": cmd_search, "download": cmd_download,
     "list": cmd_list, "adjust": cmd_adjust,
     "renormalize": cmd_renormalize, "inspect": cmd_inspect}[args.command](args)


if __name__ == "__main__":
    main()
