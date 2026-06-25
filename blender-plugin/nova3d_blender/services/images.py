# SPDX-License-Identifier: MIT
"""Reference-image validation and encoding, matching the web client's rules.

The web client accepts up to 3 images (<=8 MB each), downscales any image whose
longest side exceeds 512 px (preserving aspect ratio), re-encodes to PNG, and
sends each as a `data:` URL in the `image_artifact` list.

We reproduce that using Blender's own image API (no Pillow dependency). Because
`bpy.data.images` is not thread-safe, `encode_references` MUST be called on the
main thread — the operator does this before launching the worker, then passes
the resulting plain strings into the (bpy-free) worker.
"""

import base64
import os
import tempfile

import bpy

from .. import constants

_EXT_MIME = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".webp": "image/webp", ".bmp": "image/bmp", ".tga": "image/x-tga",
}


def _raw_data_url(path):
    """Fallback: embed the original bytes without re-encoding."""
    with open(path, "rb") as fh:
        data = fh.read()
    mime = _EXT_MIME.get(os.path.splitext(path)[1].lower(), "image/png")
    return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"


def _encode_via_blender(path):
    """Load, optionally downscale to 512 px longest side, return a PNG data URL."""
    image = bpy.data.images.load(path, check_existing=False)
    tmp_path = None
    try:
        width, height = image.size
        longest = max(width, height)
        if longest > constants.MAX_REFERENCE_IMAGE_DIMENSION:
            scale = constants.MAX_REFERENCE_IMAGE_DIMENSION / float(longest)
            image.scale(max(1, round(width * scale)), max(1, round(height * scale)))

        image.file_format = "PNG"
        handle = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        tmp_path = handle.name
        handle.close()
        image.filepath_raw = tmp_path
        image.save()

        with open(tmp_path, "rb") as fh:
            data = fh.read()
        return f"data:image/png;base64,{base64.b64encode(data).decode('ascii')}"
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        # Drop the temporary datablock so it never lingers in the .blend.
        try:
            bpy.data.images.remove(image)
        except Exception:
            pass


def encode_references(paths):
    """Validate + encode reference image paths into a list of data URLs.

    Returns (data_urls, skipped) where `skipped` is a list of (path, reason)
    for any image that was rejected, so the operator can warn the user.
    """
    data_urls = []
    skipped = []
    for path in paths:
        if len(data_urls) >= constants.MAX_REFERENCE_IMAGES:
            skipped.append((path, "image limit reached"))
            continue
        if not path or not os.path.isfile(path):
            skipped.append((path, "file not found"))
            continue
        try:
            if os.path.getsize(path) > constants.MAX_REFERENCE_IMAGE_BYTES:
                skipped.append((path, "larger than 8 MB"))
                continue
        except OSError:
            skipped.append((path, "unreadable"))
            continue
        try:
            data_urls.append(_encode_via_blender(path))
        except Exception:
            # Blender could not decode it — fall back to raw bytes.
            try:
                data_urls.append(_raw_data_url(path))
            except OSError:
                skipped.append((path, "could not read image"))
    return data_urls, skipped
