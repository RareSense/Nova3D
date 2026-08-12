# SPDX-License-Identifier: MIT
"""Check for and install a newer Nova3D add-on release from GitHub.

Network and archive work runs on short-lived worker threads, while every
``bpy`` operation stays on Blender's main thread.  The install action delegates
replacement to Blender's official extension/add-on installer; it never unzips
over a live installation itself.
"""

import queue
import threading

import bpy

from .. import constants
from ..preferences import online_access_ok
from ..services import updates


class NOVA3D_OT_check_updates(bpy.types.Operator):
    bl_idname = "nova3d.check_updates"
    bl_label = "Check for Updates"
    bl_description = "Check GitHub for a newer version of the Nova3D add-on"

    silent: bpy.props.BoolProperty(default=False, options={"HIDDEN", "SKIP_SAVE"})

    _timer = None
    _queue = None
    _thread = None

    def execute(self, context):
        if not online_access_ok():
            self.report({"WARNING"}, "Enable Preferences > System > Allow Online "
                                     "Access to check for updates.")
            return {"CANCELLED"}

        wm = context.window_manager
        if wm.nova3d_updates_busy:
            return {"CANCELLED"}
        wm.nova3d_updates_busy = True

        self._queue = queue.Queue()

        def worker(q):
            try:
                q.put(("ok", updates.fetch_latest()))
            except Exception as exc:  # noqa: BLE001 — update check must never raise
                q.put(("error", str(exc)))

        self._thread = threading.Thread(target=worker, args=(self._queue,),
                                        daemon=True, name="Nova3DUpdateCheck")
        self._thread.start()

        self._timer = wm.event_timer_add(0.2, window=context.window)
        wm.modal_handler_add(self)
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type != "TIMER":
            return {"PASS_THROUGH"}
        try:
            kind, payload = self._queue.get_nowait()
        except queue.Empty:
            return {"PASS_THROUGH"}

        wm = context.window_manager
        if kind == "ok":
            self._apply(wm, payload)
            if not self.silent:
                if wm.nova3d_update_available:
                    self.report(
                        {"INFO"},
                        f"Nova3D v{wm.nova3d_latest_version} is ready to install.",
                    )
                else:
                    self.report({"INFO"}, "Nova3D is up to date.")
        elif not self.silent:
            # Leave the previous successful state untouched on a network error.
            self.report({"WARNING"}, "Could not check for updates. Try again shortly.")
        self._finish(context)
        return {"FINISHED"}

    @staticmethod
    def _apply(wm, latest):
        """Record whether *latest* (version, str, url) beats the installed build."""
        if latest and updates.is_newer(latest[0], constants.ADDON_VERSION):
            _version, version_str, html_url = latest
            wm.nova3d_update_available = True
            wm.nova3d_latest_version = version_str
            wm.nova3d_release_url = html_url
        else:
            wm.nova3d_update_available = False
            wm.nova3d_latest_version = ""
            wm.nova3d_release_url = ""

    def _finish(self, context):
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_updates_busy = False
        for area in getattr(context.screen, "areas", []) or []:
            if area.type in ("VIEW_3D", "PREFERENCES"):
                area.tag_redraw()

    def cancel(self, context):
        self._finish(context)


class NOVA3D_OT_install_update(bpy.types.Operator):
    """Download the exact release asset and hand it to Blender's installer."""

    bl_idname = "nova3d.install_update"
    bl_label = "Update Nova3D"
    bl_description = (
        "Download the verified Nova3D release and install it using Blender; "
        "restart Blender afterward"
    )

    target_version: bpy.props.StringProperty(options={"HIDDEN", "SKIP_SAVE"})

    _timer = None
    _queue = None
    _thread = None

    def invoke(self, context, _event):
        wm = context.window_manager
        if not online_access_ok():
            self.report({"WARNING"}, "Enable Preferences > System > Allow Online "
                                     "Access to update Nova3D.")
            return {"CANCELLED"}
        if wm.nova3d_updates_busy:
            self.report({"INFO"}, "Nova3D is already checking for an update.")
            return {"CANCELLED"}
        if not wm.nova3d_update_available:
            self.report({"INFO"}, "Nova3D is already up to date. Check again if needed.")
            return {"CANCELLED"}
        self.target_version = wm.nova3d_latest_version
        return wm.invoke_props_dialog(self, width=440)

    def draw(self, _context):
        layout = self.layout
        version = self.target_version or "the latest version"
        layout.label(text=f"Install Nova3D v{version}?", icon="IMPORT")
        layout.label(text="The release is downloaded from Nova3D's GitHub repository.")
        layout.label(text="Blender's installer replaces the add-on; your settings and keys remain.")
        layout.separator()
        warning = layout.row()
        warning.alert = True
        warning.label(text="Save your work, then restart Blender after installation.",
                      icon="ERROR")

    def execute(self, context):
        if not online_access_ok():
            return {"CANCELLED"}
        wm = context.window_manager
        if wm.nova3d_updates_busy:
            return {"CANCELLED"}
        wm.nova3d_updates_busy = True

        self._queue = queue.Queue()
        blender_version = tuple(bpy.app.version)
        advertised_version = self.target_version

        def worker(q):
            try:
                release = updates.fetch_latest_release()
                if not release or not updates.is_newer(
                        release.version, constants.ADDON_VERSION):
                    raise updates.UpdateError("Nova3D is already up to date.")
                # The notice can go stale between startup and the click. A newer
                # release is safe to take, but never silently install an older
                # build than the version the confirmation named.
                advertised = updates.parse_version(advertised_version)
                if advertised and release.version < advertised:
                    raise updates.UpdateError(
                        "The advertised release is no longer available. Check again.")
                extension_path = updates.download_release(release)
                install_path = updates.install_archive_for_blender(
                    extension_path,
                    expected_version=release.version_str,
                    blender_version=blender_version,
                )
                q.put(("ok", (release, install_path)))
            except Exception as exc:  # noqa: BLE001 — report on main thread
                q.put(("error", str(exc)))

        self._thread = threading.Thread(
            target=worker,
            args=(self._queue,),
            daemon=True,
            name="Nova3DUpdateDownload",
        )
        self._thread.start()
        self._timer = wm.event_timer_add(0.2, window=context.window)
        wm.modal_handler_add(self)
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type != "TIMER":
            return {"PASS_THROUGH"}
        try:
            kind, payload = self._queue.get_nowait()
        except queue.Empty:
            return {"PASS_THROUGH"}

        self._finish(context)
        if kind == "error":
            self.report({"ERROR"}, payload or "Nova3D could not be updated.")
            return {"CANCELLED"}

        release, install_path = payload
        self.report(
            {"INFO"},
            f"Nova3D v{release.version_str} downloaded. Starting Blender's installer...",
        )
        try:
            _schedule_install(install_path, release.version_str)
        except Exception as exc:
            self.report({"ERROR"}, f"Could not start Blender's installer: {exc}")
            return {"CANCELLED"}
        return {"FINISHED"}

    def _finish(self, context):
        wm = context.window_manager
        if self._timer is not None:
            wm.event_timer_remove(self._timer)
            self._timer = None
        wm.nova3d_updates_busy = False
        for area in getattr(context.screen, "areas", []) or []:
            if area.type in ("VIEW_3D", "PREFERENCES"):
                area.tag_redraw()

    def cancel(self, context):
        # The daemon worker may finish its bounded network request, but no
        # installer is launched after the modal operator is cancelled.
        self._finish(context)


def _schedule_install(archive_path, version_str):
    """Run Blender's installer only after the Nova3D modal operator exits.

    Updating an enabled extension temporarily unloads its Python package. A
    one-shot main-thread timer means the initiating Nova3D operator has already
    returned before Blender unregisters it, avoiding an active-class teardown.
    """
    def install_once():
        try:
            _install_with_blender(archive_path)
        except Exception as exc:  # Archive remains in temp for a later retry.
            _show_update_message(
                "Nova3D update failed",
                f"Blender could not install the update: {exc}",
                icon="ERROR",
            )
        else:
            _show_update_message(
                "Nova3D update installed",
                f"Nova3D v{version_str} is installed. Restart Blender to finish.",
                icon="CHECKMARK",
            )
        return None

    bpy.app.timers.register(install_once, first_interval=0.1)


def _show_update_message(title, message, *, icon):
    def draw(popup, _context):
        popup.layout.label(text=message, icon=icon)

    try:
        bpy.context.window_manager.popup_menu(draw, title=title, icon=icon)
    except Exception:
        # A console message is still useful in background mode or during exit.
        print(f"{title}: {message}")


def _install_with_blender(archive_path):
    """Invoke the installer appropriate for how this add-on is loaded.

    Modern extensions carry a ``bl_ext.<repo>`` namespace; passing that exact
    repository is essential so Blender upgrades the existing extension instead
    of installing a duplicate elsewhere. Legacy installs use Blender's normal
    overwrite operator with the repacked one-folder archive.
    """
    repo = updates.extension_repo_from_package(__package__)
    if tuple(bpy.app.version) >= (4, 2, 0) and repo:
        result = bpy.ops.extensions.package_install_files(
            "EXEC_DEFAULT",
            filepath=archive_path,
            repo=repo,
            enable_on_install=True,
        )
    else:
        result = bpy.ops.preferences.addon_install(
            "EXEC_DEFAULT", filepath=archive_path, overwrite=True,
        )
    if "CANCELLED" in result:
        raise RuntimeError("Blender's add-on installer cancelled the update.")
    return result
