# SPDX-License-Identifier: MIT
"""Reference-image management operators (add / remove / clear).

Up to 3 images may be attached, matching the web client. Selection uses
Blender's file browser; the chosen paths are stored on the scene and encoded to
data URLs only at generation time (on the main thread).
"""

import os

import bpy
from bpy_extras.io_utils import ImportHelper

from .. import constants


class NOVA3D_OT_add_images(bpy.types.Operator, ImportHelper):
    bl_idname = "nova3d.add_images"
    bl_label = "Add Reference Image"
    bl_description = "Attach up to 3 reference images to guide the generation"

    # ImportHelper provides `filepath`; `files` holds a multi-selection.
    filter_glob: bpy.props.StringProperty(
        default="*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.tga", options={"HIDDEN"})
    files: bpy.props.CollectionProperty(
        type=bpy.types.OperatorFileListElement, options={"HIDDEN", "SKIP_SAVE"})
    directory: bpy.props.StringProperty(subtype="DIR_PATH", options={"HIDDEN"})

    def execute(self, context):
        scene = context.scene
        existing = {img.path for img in scene.nova3d_images}
        selected = [f.name for f in self.files if f.name] or (
            [os.path.basename(self.filepath)] if self.filepath else [])

        added = 0
        for name in selected:
            if len(scene.nova3d_images) >= constants.MAX_REFERENCE_IMAGES:
                self.report({"WARNING"},
                            f"At most {constants.MAX_REFERENCE_IMAGES} images.")
                break
            path = os.path.join(self.directory, name) if self.directory else name
            if path in existing:
                continue
            item = scene.nova3d_images.add()
            item.path = path
            existing.add(path)
            added += 1

        if added:
            scene.nova3d_images_index = len(scene.nova3d_images) - 1
            self.report({"INFO"}, f"Added {added} reference image(s).")
        return {"FINISHED"}


class NOVA3D_OT_remove_image(bpy.types.Operator):
    bl_idname = "nova3d.remove_image"
    bl_label = "Remove Reference Image"
    bl_description = "Remove the selected reference image"

    index: bpy.props.IntProperty(default=-1)

    def execute(self, context):
        scene = context.scene
        idx = self.index if self.index >= 0 else scene.nova3d_images_index
        if 0 <= idx < len(scene.nova3d_images):
            scene.nova3d_images.remove(idx)
            scene.nova3d_images_index = min(idx, len(scene.nova3d_images) - 1)
        return {"FINISHED"}


class NOVA3D_OT_clear_images(bpy.types.Operator):
    bl_idname = "nova3d.clear_images"
    bl_label = "Clear Reference Images"
    bl_description = "Remove all reference images"

    def execute(self, context):
        context.scene.nova3d_images.clear()
        context.scene.nova3d_images_index = 0
        return {"FINISHED"}
