# SPDX-License-Identifier: MIT
"""Nova3D — Code-native 3D generation, natively inside Blender.

This add-on drives the hosted Nova3D / GraphFlow backend (the same service the
web app uses) to generate part-structured 3D assets from a text prompt and
optional reference images. Generations are billed in Nova3D credits, written to
a per-generation project folder on disk, imported into the scene, and synced to
the user's web chat history.

It requires ZERO backend changes: every call uses the public GraphFlow API with
the user's Nova3D API key. See ``README.md`` for the full data flow.

Package layout
--------------
    constants.py        endpoints, model catalogue, limits, labels
    preferences.py      API key, base URLs, output folder
    properties.py       scene inputs + transient runtime state
    api/                stdlib HTTP + typed client + result parsing (no bpy)
    services/           generation worker, history, project store, UV, images
    scene_io/           GLB import + collections + text datablock (main thread)
    operators/          account, image management, the modal Generate operator
    ui/                 the N-panel
"""

bl_info = {
    "name": "Nova3D — Code-native 3D Generation",
    "author": "RareSense (Nova3D)",
    "version": (1, 0, 0),
    "blender": (3, 6, 0),
    "location": "View3D > Sidebar (N) > Nova3D",
    "description": "Generate part-structured 3D assets from text prompts using "
                   "the hosted Nova3D backend and your Nova3D credits.",
    "category": "3D View",
    "doc_url": "https://nova3d.xyz",
    "tracker_url": "https://github.com/RareSense/Nova3D/issues",
}

import bpy

from . import preferences, properties
from . import operators, ui


def register():
    bpy.utils.register_class(preferences.Nova3DPreferences)
    properties.register_properties()
    for cls in operators.classes:
        bpy.utils.register_class(cls)
    for cls in ui.classes:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(ui.classes):
        bpy.utils.unregister_class(cls)
    for cls in reversed(operators.classes):
        bpy.utils.unregister_class(cls)
    properties.unregister_properties()
    bpy.utils.unregister_class(preferences.Nova3DPreferences)


if __name__ == "__main__":
    register()
