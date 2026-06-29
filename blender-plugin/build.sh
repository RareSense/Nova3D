#!/usr/bin/env bash
#
# Reproducible build of the Nova3D Blender extension.
#
# Produces  dist/<id>-<version>.zip  with blender_manifest.toml at the archive
# ROOT, which is what Blender 4.2+/5.x "Install from Disk" requires. The id and
# version are read straight from the manifest, so the zip name always matches.
#
# Usage:   bash build.sh
# Output:  blender-plugin/dist/nova3d_blender-<version>.zip
#
# Dependency-free: uses Python's stdlib `zipfile` (no `zip` binary, no venv, no
# pip packages), so local and CI builds are identical.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null || { echo "error: python3 is required to build" >&2; exit 1; }

python3 - "$SCRIPT_DIR" <<'PY'
import os, re, sys, zipfile

root = sys.argv[1]
pkg_dir = os.path.join(root, "nova3d_blender")
dist_dir = os.path.join(root, "dist")
manifest = os.path.join(pkg_dir, "blender_manifest.toml")

if not os.path.isfile(manifest):
    sys.exit(f"error: manifest not found at {manifest}")

text = open(manifest, encoding="utf-8").read()
def field(name):
    m = re.search(rf'^{name}\s*=\s*"([^"]+)"', text, re.M)
    return m.group(1) if m else None
ext_id, version = field("id"), field("version")
if not ext_id or not version:
    sys.exit("error: could not read id/version from manifest")

os.makedirs(dist_dir, exist_ok=True)
out = os.path.join(dist_dir, f"{ext_id}-{version}.zip")
if os.path.exists(out):
    os.remove(out)

# Add every file with a path RELATIVE to the package dir, so the manifest lands
# at the archive root. Skip bytecode so a stale __pycache__ never ships.
def keep(rel):
    parts = rel.split(os.sep)
    if "__pycache__" in parts:
        return False
    return not rel.endswith((".pyc", ".pyo"))

names = []
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for dirpath, dirnames, filenames in os.walk(pkg_dir):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for fn in sorted(filenames):
            abs_path = os.path.join(dirpath, fn)
            rel = os.path.relpath(abs_path, pkg_dir)
            if keep(rel):
                zf.write(abs_path, rel)
                names.append(rel)

# Hard requirement for an extension: the manifest must be at the archive root.
if "blender_manifest.toml" not in names:
    sys.exit("error: blender_manifest.toml is not at the archive root — bad layout")

print(f"Built: {out}")
print("Contents:")
for n in sorted(names):
    print("  " + n)
PY
