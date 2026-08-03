# SPDX-License-Identifier: MIT
"""Business logic: generation pipeline, history sync, project folders, UV maps.

These modules run on a worker thread and must not touch `bpy` (the only
exception is `images.py`, whose encode step runs on the main thread before the
worker starts). All Blender data-model work happens in `scene_io` on the main
thread.
"""
