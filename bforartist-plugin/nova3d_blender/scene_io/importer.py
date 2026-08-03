# SPDX-License-Identifier: MIT
"""Import a generated GLB into the scene, non-destructively.

Design goals (per the spec):
  * Show the freshly generated model.
  * Auto-hide previously generated Nova3D collections so only the newest shows.
  * NEVER wipe the scene or delete the user's other objects.
  * Load the asset's `code.py` into Blender's Text Editor as a re-runnable
    datablock.

Each generation lands in its own collection named ``Nova3D_<slug>`` (tagged with
a custom property), which is how we find and hide prior generations.
"""

import bpy

from .. import constants
from ..preferences import get_prefs


def _iter_generation_collections():
    """Yield every collection this add-on created (current or past)."""
    for coll in bpy.data.collections:
        if coll.get(constants.GENERATED_TAG) or coll.name.startswith(constants.COLLECTION_PREFIX):
            yield coll


def _find_layer_collection(layer_collection, name):
    """Depth-first search for the LayerCollection matching *name*."""
    if layer_collection.collection.name == name:
        return layer_collection
    for child in layer_collection.children:
        found = _find_layer_collection(child, name)
        if found:
            return found
    return None


def hide_previous_generations(context, *, keep_name=None):
    """Hide (never delete) every prior Nova3D generation collection."""
    view_layer = context.view_layer
    for coll in _iter_generation_collections():
        if coll.name == keep_name:
            continue
        coll.hide_viewport = True
        coll.hide_render = True
        layer = _find_layer_collection(view_layer.layer_collection, coll.name)
        if layer is not None:
            layer.exclude = True


def _unique_collection_name(slug):
    base = f"{constants.COLLECTION_PREFIX}{slug}"
    name = base
    index = 1
    while name in bpy.data.collections:
        name = f"{base}_{index:02d}"
        index += 1
    return name


def import_generation(context, *, glb_path, slug):
    """Create a fresh collection, import the GLB into it, hide older ones.

    Returns the new collection, or None if the import failed.
    """
    scene = context.scene
    view_layer = context.view_layer

    collection = bpy.data.collections.new(_unique_collection_name(slug))
    collection[constants.GENERATED_TAG] = True
    scene.collection.children.link(collection)

    # Make the new collection active so the glTF importer drops objects into it.
    layer = _find_layer_collection(view_layer.layer_collection, collection.name)
    previous_active = view_layer.active_layer_collection
    if layer is not None:
        layer.exclude = False
        view_layer.active_layer_collection = layer

    try:
        bpy.ops.import_scene.gltf(filepath=glb_path)
    except Exception:
        # Roll back the empty collection so a failed import leaves no orphan.
        if previous_active is not None:
            view_layer.active_layer_collection = previous_active
        try:
            scene.collection.children.unlink(collection)
            bpy.data.collections.remove(collection)
        except Exception:
            pass
        return None

    # Hide prior generations only after a successful import of the new one.
    hide_previous_generations(context, keep_name=collection.name)

    # "Clean viewport" (default on, reversible): hide everything else so only the
    # new generation shows, and switch Solid shading to Material Preview so the
    # asset's colours appear (Solid mode renders flat grey). Users with a real
    # scene can turn this off in preferences.
    prefs = get_prefs(context)
    if prefs is None or prefs.clean_viewport:
        _isolate_collection(context, collection)
        _enable_material_preview(context)

    _focus_collection(context, collection)
    return collection


def _isolate_collection(context, keep_collection):
    """Hide (reversibly) every object that is not in the new collection."""
    keep = set(keep_collection.objects)
    for obj in context.view_layer.objects:
        if obj not in keep:
            try:
                obj.hide_set(True)  # eye toggle — restore with Alt+H / the Outliner
            except Exception:
                pass


def _enable_material_preview(context):
    """Show materials in the viewport (Solid mode renders flat grey)."""
    for area in context.window.screen.areas:
        if area.type != "VIEW_3D":
            continue
        space = area.spaces.active
        try:
            if space.shading.type in ("SOLID", "WIREFRAME"):
                space.shading.type = "MATERIAL"
        except Exception:
            pass
        break


def _focus_collection(context, collection):
    """Select the new objects and frame the viewport on them."""
    objects = list(collection.objects)
    if not objects:
        return
    try:
        bpy.ops.object.select_all(action="DESELECT")
    except Exception:
        pass
    for obj in objects:
        try:
            obj.select_set(True)
        except Exception:
            pass
    context.view_layer.objects.active = objects[0]
    for area in context.window.screen.areas:
        if area.type != "VIEW_3D":
            continue
        region = next((r for r in area.regions if r.type == "WINDOW"), None)
        if region is None:
            continue
        try:
            with context.temp_override(area=area, region=region):
                bpy.ops.view3d.view_selected(use_all_regions=False)
        except Exception:
            pass  # framing is a convenience; never let it break the import
        break


def load_code_text(slug, code_text):
    """Create/replace a Text datablock holding the asset's source program.

    Returns the Text datablock, or None if there was no code.
    """
    if not code_text:
        return None
    name = f"{slug}.py"
    text = bpy.data.texts.get(name)
    if text is None:
        text = bpy.data.texts.new(name)
    text.clear()
    text.write(code_text)
    text[constants.GENERATED_TAG] = True
    _show_text_in_editor(text)
    return text


def _show_text_in_editor(text):
    """If a Text Editor is open, point it at the new datablock."""
    try:
        for window in bpy.context.window_manager.windows:
            for area in window.screen.areas:
                if area.type == "TEXT_EDITOR":
                    area.spaces.active.text = text
                    return
    except Exception:
        pass
