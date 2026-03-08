#!/usr/bin/env python3
"""
Interactive Mixamo animation tool — search, download, and retarget onto the cat.

Usage:
  # First time: get your token from Mixamo
  #   1. Log in to mixamo.com
  #   2. Open browser devtools → Console
  #   3. Run: JSON.parse(localStorage.getItem("persist:root")).access_token.replace(/"/g,'')
  #   4. Save it:
  echo "YOUR_TOKEN" > ~/.mixamo_token

  # Search for animations:
  python3 mixamo_tool.py search "dance"
  python3 mixamo_tool.py search "walk" --limit 20

  # Download animations (by ID from search results):
  python3 mixamo_tool.py download ID1 ID2 ID3

  # Download by name (searches, picks best match):
  python3 mixamo_tool.py get "Waving" "Clapping" "Sitting"

  # List all downloaded FBX files:
  python3 mixamo_tool.py list

  # Retarget all new FBX files onto the cat:
  python3 mixamo_tool.py retarget

  # Do everything: search → pick → download → retarget
  python3 mixamo_tool.py get "Waving" "Backflip" --retarget
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import urllib.error

API_BASE = "https://www.mixamo.com/api/v1"
API_KEY = "mixamo2"
DEFAULT_CHARACTER = "4f5d21e1-4ccc-41f1-b35b-fb2547bd8493"  # Y Bot
DOWNLOAD_DIR = "/tmp/mixamo-downloads"
TOKEN_FILE = os.path.expanduser("~/.mixamo_token")
ENV_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")

# What we already have retargeted (skip these)
EXISTING_ANIMS = {
    "Breakdance", "Catwalk", "Chicken", "Drunk", "Hip_Hop_Dancing",
    "Idle", "Jumping", "Running", "Silly", "Sneak", "Strut_Walking",
    "Walking", "Zombie",
}

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
RETARGET_SCRIPT = os.path.join(PROJECT_DIR, "retarget_mixamo.py")
BLENDER = os.path.expanduser("~/projects/game-a-day/apps/blender/blender")


def get_token(args_token=None):
    if args_token:
        return args_token.strip()
    # Check .env file
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("MIXAMO_TOKEN="):
                    token = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if token:
                        return token
    # Check ~/.mixamo_token
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            token = f.read().strip().strip('"')
            if token:
                return token
    print("No token found. Get one from Mixamo:")
    print("  1. Log in to https://www.mixamo.com")
    print("  2. Browser devtools → Console →")
    print('     localStorage.getItem("access_token")')
    print(f"  3. Save it to .env: MIXAMO_TOKEN=your_token_here")
    sys.exit(1)


def api_get(path, token):
    url = f"{API_BASE}/{path}" if not path.startswith("http") else path
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "X-Api-Key": API_KEY,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:200]
        if e.code == 401:
            print(f"Token expired. Get a new one and save to {TOKEN_FILE}")
            sys.exit(1)
        print(f"HTTP {e.code}: {body}")
        raise


def api_post(path, token, data):
    url = f"{API_BASE}/{path}"
    body = json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": f"Bearer {token}",
        "X-Api-Key": API_KEY,
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()[:200]}")
        raise


def cmd_search(args):
    token = get_token(args.token)
    query = " ".join(args.query)
    data = api_get(f"products?page=1&limit={args.limit}&type=Motion&query={urllib.parse.quote(query)}", token)
    results = data.get("results", [])
    if not results:
        print(f"No results for '{query}'")
        return

    print(f"\n{'ID':<40} {'Name':<35} {'Duration'}")
    print("-" * 85)
    for p in results:
        pid = p["id"]
        name = p["name"]
        dur = p.get("details", {}).get("duration", "?")
        if isinstance(dur, (int, float)):
            dur = f"{dur:.1f}s"
        print(f"{pid:<40} {name:<35} {dur}")
    print(f"\nTo download: python3 mixamo_tool.py get \"{results[0]['name']}\"")


def _build_gms_hash(gms_hash_raw):
    """Normalize gms_hash dict to match the browser's export format."""
    raw_trim = gms_hash_raw.get("trim", [0, 100])
    return {
        "model-id": gms_hash_raw["model-id"],
        "mirror": gms_hash_raw.get("mirror", False),
        "trim": [int(raw_trim[0]), int(raw_trim[1])],
        "overdrive": 0,
        "params": "0,0,0",
        "arm-space": gms_hash_raw.get("arm-space", 0),
        "inplace": gms_hash_raw.get("inplace", False),
    }


def _export_animation(token, pid, pname):
    """Try to export an animation. Returns download URL or None."""
    details = api_get(f"products/{pid}?similar=0&character_id={DEFAULT_CHARACTER}", token)
    gms_hash_raw = details.get("details", {}).get("gms_hash")
    if not gms_hash_raw:
        print(f"    No gms_hash for {pname}")
        return None

    gms_hash = _build_gms_hash(gms_hash_raw)
    api_post("animations/export", token, {
        "gms_hash": [gms_hash],
        "preferences": {"format": "fbx7_2019", "skin": "false", "fps": "30", "reducekf": "0"},
        "character_id": DEFAULT_CHARACTER,
        "type": "Motion",
        "product_name": pname,
    })

    # Poll for completion
    for _ in range(30):
        time.sleep(2)
        result = api_get(f"characters/{DEFAULT_CHARACTER}/monitor", token)
        status = result.get("status")
        if status == "completed":
            return result.get("job_result")
        elif status == "failed":
            msg = result.get("job_result", {}).get("message", "unknown")
            print(f"    Export failed: {msg}")
            return None
    print(f"    Export timed out")
    return None


def cmd_get(args):
    token = get_token(args.token)
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)
    downloaded = []

    for name in args.names:
        # Search for matches (try multiple in case first fails)
        data = api_get(f"products?page=1&limit=10&type=Motion&query={urllib.parse.quote(name)}", token)
        results = data.get("results", [])
        if not results:
            print(f"  No results for '{name}', skipping")
            continue

        # Try each result until one exports successfully (max 3 attempts)
        max_attempts = 3
        success = False
        for idx, product in enumerate(results[:max_attempts]):
            pid = product["id"]
            pname = product["name"]
            safe_name = pname.replace(" ", "_").replace("/", "_")
            output_path = os.path.join(DOWNLOAD_DIR, f"{safe_name}.fbx")

            if os.path.exists(output_path):
                print(f"  SKIP (exists): {safe_name}.fbx")
                downloaded.append((output_path, safe_name))
                success = True
                break

            attempt = f" (attempt {idx+1}/{max_attempts})" if idx > 0 else ""
            print(f"  Downloading: {pname}{attempt}")

            download_url = _export_animation(token, pid, pname)
            if not download_url:
                if idx < max_attempts - 1:
                    print(f"    Trying next result...")
                    time.sleep(1)
                continue

            # Download the FBX
            req = urllib.request.Request(download_url)
            with urllib.request.urlopen(req, timeout=60) as resp:
                with open(output_path, "wb") as f:
                    f.write(resp.read())

            print(f"    OK: {safe_name}.fbx")
            downloaded.append((output_path, safe_name))
            success = True
            break

        if not success:
            print(f"  FAILED: Could not export any variant of '{name}'")

    print(f"\nDownloaded {len(downloaded)} animations to {DOWNLOAD_DIR}/")

    if args.retarget and downloaded:
        print("\nRetargeting onto cat...\n")
        _retarget_files(downloaded)


def cmd_download(args):
    """Download by product IDs."""
    token = get_token(args.token)
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)

    for pid in args.ids:
        details = api_get(f"products/{pid}?similar=0&character_id={DEFAULT_CHARACTER}", token)
        name = details.get("name", pid)
        print(f"  Found: {name}")
        # Reuse the get logic
        args.names = [name]
        args.retarget = False
        cmd_get(args)
        time.sleep(1)


def cmd_list(args):
    if not os.path.exists(DOWNLOAD_DIR):
        print("No downloads yet")
        return
    fbx_files = sorted(f for f in os.listdir(DOWNLOAD_DIR) if f.endswith(".fbx"))
    retargeted = _get_retargeted_anims()

    print(f"\n{'File':<40} {'Status'}")
    print("-" * 55)
    for f in fbx_files:
        name = f.replace(".fbx", "")
        if name in retargeted:
            status = "retargeted"
        else:
            status = "NEW — needs retarget"
        print(f"{f:<40} {status}")
    print(f"\n{len(fbx_files)} FBX files in {DOWNLOAD_DIR}/")


def _get_retargeted_anims():
    """Check which animations are already in the cat GLTF."""
    gltf_path = os.path.join(PROJECT_DIR, "cartoon_cat.gltf")
    if not os.path.exists(gltf_path):
        return set()
    with open(gltf_path) as f:
        data = json.load(f)
    return {a["name"].replace("Cat_", "") for a in data.get("animations", [])}


def cmd_retarget(args):
    if not os.path.exists(DOWNLOAD_DIR):
        print("No downloads to retarget")
        return

    fbx_files = sorted(f for f in os.listdir(DOWNLOAD_DIR) if f.endswith(".fbx"))
    retargeted = _get_retargeted_anims()

    # Find new FBX files that haven't been retargeted
    to_retarget = []
    for f in fbx_files:
        name = f.replace(".fbx", "")
        # Build the cat animation name
        cat_name = "Cat_" + name.replace(" ", "").replace("-", "")
        if cat_name.replace("Cat_", "") not in retargeted and name not in EXISTING_ANIMS:
            to_retarget.append((os.path.join(DOWNLOAD_DIR, f), cat_name))

    if not to_retarget:
        print("All downloaded animations are already retargeted")
        return

    _retarget_files(to_retarget)


def _retarget_files(file_pairs):
    """Run retarget_mixamo.py as a Python script (it invokes Blender internally)."""
    if not os.path.exists(RETARGET_SCRIPT):
        print(f"Retarget script not found at {RETARGET_SCRIPT}")
        return

    # Build args: pairs of "fbx_path" "CatAnimName"
    retarget_args = []
    for fbx_path, cat_name in file_pairs:
        retarget_args.extend([fbx_path, cat_name])
        print(f"  {os.path.basename(fbx_path)} → {cat_name}")

    cmd = [sys.executable, RETARGET_SCRIPT] + retarget_args

    print(f"\nRunning retarget ({len(file_pairs)} animations)...")
    result = subprocess.run(cmd, text=True, timeout=600)
    if result.returncode == 0:
        print("Retarget complete!")
    else:
        print(f"Retarget failed (exit {result.returncode})")


def main():
    parser = argparse.ArgumentParser(
        description="Mixamo animation tool — search, download, retarget",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  %(prog)s search "dance"              Search for dance animations
  %(prog)s search "wave" --limit 20    Search with more results
  %(prog)s get "Waving" "Clapping"     Download by name (best match)
  %(prog)s get "Backflip" --retarget   Download and retarget onto cat
  %(prog)s list                        Show downloaded FBX files
  %(prog)s retarget                    Retarget all new downloads
""")
    parser.add_argument("--token", help="Mixamo bearer token (or save to ~/.mixamo_token)")

    sub = parser.add_subparsers(dest="command")

    p_search = sub.add_parser("search", help="Search Mixamo animations")
    p_search.add_argument("query", nargs="+", help="Search terms")
    p_search.add_argument("--limit", type=int, default=10, help="Max results (default 10)")

    p_get = sub.add_parser("get", help="Download animations by name")
    p_get.add_argument("names", nargs="+", help="Animation names to search and download")
    p_get.add_argument("--retarget", action="store_true", help="Also retarget onto cat")

    p_dl = sub.add_parser("download", help="Download by Mixamo product IDs")
    p_dl.add_argument("ids", nargs="+", help="Product IDs")

    p_list = sub.add_parser("list", help="List downloaded animations")

    p_ret = sub.add_parser("retarget", help="Retarget new downloads onto cat")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return

    {"search": cmd_search, "get": cmd_get, "download": cmd_download,
     "list": cmd_list, "retarget": cmd_retarget}[args.command](args)


if __name__ == "__main__":
    main()
