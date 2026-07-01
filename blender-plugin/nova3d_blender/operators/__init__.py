# SPDX-License-Identifier: MIT
"""Blender operators: account/credits actions, image management, generation."""

from . import account, images, generate, auth, updates

# Registration order does not matter for these classes; listed for the central
# register() in the add-on's __init__.
classes = (
    account.NOVA3D_OT_open_api_key,
    account.NOVA3D_OT_buy_credits,
    account.NOVA3D_OT_refresh_credits,
    account.NOVA3D_OT_open_output_folder,
    account.NOVA3D_OT_copy_workflow_id,
    updates.NOVA3D_OT_check_updates,
    auth.NOVA3D_OT_sign_in,
    auth.NOVA3D_OT_enter_api_key,
    auth.NOVA3D_OT_sign_out,
    images.NOVA3D_OT_add_images,
    images.NOVA3D_OT_remove_image,
    images.NOVA3D_OT_clear_images,
    generate.NOVA3D_OT_generate,
    generate.NOVA3D_OT_resume,
    generate.NOVA3D_OT_cancel,
)
