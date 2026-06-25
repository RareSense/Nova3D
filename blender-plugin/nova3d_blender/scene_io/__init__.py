# SPDX-License-Identifier: MIT
"""Blender data-model operations (GLB import, collections, text datablocks).

Everything here runs on the main thread, invoked by the generate operator when
the worker signals that an asset is ready on disk.
"""
