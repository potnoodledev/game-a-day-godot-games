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

# Target hat height in Blender units (cat is scaled 0.25x in Godot,
# head is roughly 0.8 units in model space)
TARGET_HEIGHT = 0.4


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
        "offset": [0.0, 0.08, 0.0],
        "rotation": [0.0, 0.0, 0.0],
        "scale": [1.0, 1.0, 1.0],
        "source_uid": uid,
        "license": license_label,
        "author": author,
    }
    save_registry(registry)
    print(f"  Registry updated. Adjust offset/rotation/scale in hat_registry.json if needed.")


def _normalize_hat(input_file, output_glb, tmp_dir):
    """Run Blender to normalize hat: center origin, scale, orient, export as GLB."""
    is_glb = input_file.endswith(".glb")
    import_op = "bpy.ops.import_scene.gltf" if not is_glb else "bpy.ops.import_scene.gltf"

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

# Select all meshes
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]

# Join into one mesh
if len(meshes) > 1:
    bpy.ops.object.join()

obj = bpy.context.active_object

# Apply all transforms
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Set origin to bottom-center of bounding box
bbox = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
min_y = min(v.z for v in bbox)  # Z is up in Blender
center_x = sum(v.x for v in bbox) / 8
center_y = sum(v.y for v in bbox) / 8

# Move geometry so origin is at bottom-center
offset = mathutils.Vector((-center_x, -center_y, -min_y))
obj.data.transform(mathutils.Matrix.Translation(offset))
obj.location = (0, 0, 0)

# Scale to target height
bbox2 = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
height = max(v.z for v in bbox2) - min(v.z for v in bbox2)
if height > 0:
    scale_factor = {TARGET_HEIGHT} / height
    obj.scale = (scale_factor, scale_factor, scale_factor)
    bpy.ops.object.transform_apply(scale=True)

# Clear rotation
obj.rotation_euler = (0, 0, 0)

# Resize all textures to max 256x256 to keep GLB small
MAX_TEX = 256
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

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return

    {"search": cmd_search, "download": cmd_download,
     "list": cmd_list, "adjust": cmd_adjust}[args.command](args)


if __name__ == "__main__":
    main()
