# SPDX-License-Identifier: MIT
"""HTTP transport + typed client for the hosted Nova3D / GraphFlow API.

This package is intentionally free of any `bpy` import so it can run inside a
worker thread without touching Blender's (non-thread-safe) data model.
"""
