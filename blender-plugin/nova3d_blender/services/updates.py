# SPDX-License-Identifier: MIT
"""Discover, download, and validate Nova3D Blender add-on releases.

This module deliberately has no :mod:`bpy` dependency.  GitHub requests and
archive I/O are blocking and must be run by an operator worker thread.

The updater never extracts files into Blender's add-on directory itself.  It
downloads the exact asset attached to the matching GitHub release, validates
its identity and version, then hands the archive to Blender's own installer.
That lets Blender own replacement/rollback details and keeps user preferences
(including API keys) separate from the installed code.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import PurePosixPath
import re
import shutil
import ssl
import stat
import tempfile
from typing import NamedTuple
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from .. import constants
from ..api import http


_VERSION_RE = re.compile(r"(\d+)\.(\d+)\.(\d+)")
_MANIFEST_FIELD_RE = re.compile(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"\s*(?:#.*)?$', re.MULTILINE,
)
_SSL_CONTEXT = ssl.create_default_context()


class UpdateError(RuntimeError):
    """A safe, actionable update error that may be shown to the user."""


class ReleaseInfo(NamedTuple):
    """A published Nova3D release and its exact Blender extension asset."""

    version: tuple[int, int, int]
    version_str: str
    html_url: str
    asset_url: str
    asset_name: str
    asset_size: int
    asset_digest: str

    @property
    def notice(self):
        """Legacy three-tuple consumed by the existing update notice."""
        return self.version, self.version_str, self.html_url


def parse_version(text):
    """Extract a ``(major, minor, patch)`` tuple from a tag/version string."""
    match = _VERSION_RE.search(text or "")
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def is_newer(latest, current):
    """True when *latest* is a strictly higher version tuple than *current*."""
    return bool(latest) and bool(current) and latest > current


def expected_asset_name(version_str):
    return constants.UPDATE_ASSET_NAME_TEMPLATE.format(version=version_str)


def _release_info(release, *, tag_prefix):
    if not isinstance(release, dict):
        return None
    if release.get("draft") or release.get("prerelease"):
        return None

    tag = release.get("tag_name") or ""
    if tag_prefix and not tag.startswith(tag_prefix):
        return None
    version = parse_version(tag)
    if not version:
        return None
    version_str = ".".join(str(part) for part in version)
    # Reject suffixes such as v1.2.3-rc1 even if GitHub forgot to mark them as
    # prereleases. Stable add-on tags have one exact, predictable shape.
    if tag != f"{tag_prefix}{version_str}":
        return None

    asset_name = expected_asset_name(version_str)
    asset = next(
        (
            candidate for candidate in (release.get("assets") or [])
            if isinstance(candidate, dict) and candidate.get("name") == asset_name
        ),
        None,
    )
    if not asset:
        return None
    asset_url = asset.get("browser_download_url") or ""
    if not _trusted_asset_url(asset_url, tag=tag, asset_name=asset_name):
        return None

    try:
        asset_size = int(asset.get("size") or 0)
    except (TypeError, ValueError):
        asset_size = 0
    if asset_size < 0 or asset_size > constants.UPDATE_MAX_DOWNLOAD_BYTES:
        return None

    digest = asset.get("digest") or ""
    if digest and not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
        return None
    return ReleaseInfo(
        version=version,
        version_str=version_str,
        html_url=release.get("html_url") or constants.RELEASES_PAGE_URL,
        asset_url=asset_url,
        asset_name=asset_name,
        asset_size=asset_size,
        asset_digest=digest.lower(),
    )


def _trusted_asset_url(url, *, tag, asset_name):
    """Only accept the release-asset path owned by the Nova3D repository."""
    try:
        parsed = urllib.parse.urlsplit(url)
    except (TypeError, ValueError):
        return False
    expected_path = (
        f"/RareSense/Nova3D/releases/download/"
        f"{urllib.parse.quote(tag, safe='')}/{urllib.parse.quote(asset_name, safe='')}"
    )
    return (
        parsed.scheme == "https"
        and (parsed.hostname or "").lower() == "github.com"
        and parsed.path == expected_path
        and not parsed.username
        and not parsed.password
        and not parsed.query
        and not parsed.fragment
    )


def fetch_latest_release(*, api_url=None, tag_prefix=None, timeout=None):
    """Return the highest stable release with the matching installable asset.

    GitHub's release ordering is based on creation time, which need not match
    semantic-version order after backfills.  Selecting the maximum version is
    deterministic and prevents an older late-published release being offered.
    """
    api_url = api_url or constants.GITHUB_RELEASES_API
    tag_prefix = tag_prefix if tag_prefix is not None else constants.RELEASE_TAG_PREFIX
    timeout = timeout or constants.UPDATE_HTTP_TIMEOUT
    releases = http.request_json(
        "GET", api_url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "nova3d-blender-addon",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        timeout=timeout,
    )
    if not isinstance(releases, list):
        return None
    candidates = [
        info for release in releases
        if (info := _release_info(release, tag_prefix=tag_prefix)) is not None
    ]
    return max(candidates, key=lambda info: info.version, default=None)


def fetch_latest(*, api_url=None, tag_prefix=None, timeout=None):
    """Return the legacy ``(version, version_str, html_url)`` notice tuple.

    Kept as a small compatibility wrapper for callers that only need to display
    the newest version.  New installation code should use
    :func:`fetch_latest_release` so it also gets the validated asset metadata.
    """
    latest = fetch_latest_release(
        api_url=api_url, tag_prefix=tag_prefix, timeout=timeout,
    )
    return latest.notice if latest else None


def download_release(release, *, destination_dir=None, timeout=None):
    """Download and validate *release*; return the local extension ZIP path.

    The download is streamed into a sibling ``.part`` file, bounded in size,
    SHA-256 checked when GitHub supplies a digest, archive-validated, and only
    then atomically renamed.  A failed download can therefore never be mistaken
    for an installable update.
    """
    if not isinstance(release, ReleaseInfo):
        raise UpdateError("The update metadata was invalid. Check again and retry.")
    tag = f"{constants.RELEASE_TAG_PREFIX}{release.version_str}"
    if release.asset_name != expected_asset_name(release.version_str) or not _trusted_asset_url(
            release.asset_url, tag=tag, asset_name=release.asset_name):
        raise UpdateError("The release did not contain the expected Nova3D add-on package.")

    destination_dir = destination_dir or os.path.join(
        tempfile.gettempdir(), constants.UPDATE_CACHE_DIRNAME,
    )
    try:
        os.makedirs(destination_dir, exist_ok=True)
    except OSError as exc:
        raise UpdateError(f"Could not create the temporary update folder: {exc}") from None

    destination = os.path.join(destination_dir, release.asset_name)
    partial = destination + ".part"
    digest = hashlib.sha256()
    total = 0
    request = urllib.request.Request(
        release.asset_url,
        headers={"Accept": "application/octet-stream", "User-Agent": "nova3d-blender-addon"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(
                request, timeout=timeout or constants.UPDATE_DOWNLOAD_TIMEOUT,
                context=_SSL_CONTEXT) as response, open(partial, "wb") as output:
            content_length = response.headers.get("Content-Length")
            if content_length:
                try:
                    declared = int(content_length)
                except ValueError:
                    declared = 0
                if declared > constants.UPDATE_MAX_DOWNLOAD_BYTES:
                    raise UpdateError("The update package is unexpectedly large.")
            while True:
                chunk = response.read(1 << 16)
                if not chunk:
                    break
                total += len(chunk)
                if total > constants.UPDATE_MAX_DOWNLOAD_BYTES:
                    raise UpdateError("The update package is unexpectedly large.")
                output.write(chunk)
                digest.update(chunk)
    except UpdateError:
        _remove_if_exists(partial)
        raise
    except (urllib.error.URLError, TimeoutError, ssl.SSLError, OSError) as exc:
        _remove_if_exists(partial)
        reason = getattr(exc, "reason", exc)
        raise UpdateError(f"Could not download the update: {reason}") from None

    if release.asset_size and total != release.asset_size:
        _remove_if_exists(partial)
        raise UpdateError("The update download was incomplete. Please retry.")
    if release.asset_digest:
        expected_digest = release.asset_digest.partition(":")[2]
        if digest.hexdigest().lower() != expected_digest:
            _remove_if_exists(partial)
            raise UpdateError("The update package failed its integrity check.")

    try:
        validate_release_archive(partial, expected_version=release.version_str)
        os.replace(partial, destination)
    except UpdateError:
        _remove_if_exists(partial)
        raise
    except OSError as exc:
        _remove_if_exists(partial)
        raise UpdateError(f"Could not finish saving the update: {exc}") from None
    return destination


def validate_release_archive(path, *, expected_version):
    """Validate package layout, identity, version, and bounded ZIP contents."""
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            names = [info.filename for info in infos]
            if len(names) != len(set(names)):
                raise UpdateError("The update package contains duplicate files.")
            total_uncompressed = 0
            for info in infos:
                if not _safe_member(info):
                    raise UpdateError("The update package contains an unsafe file path.")
                total_uncompressed += info.file_size
                if total_uncompressed > constants.UPDATE_MAX_UNCOMPRESSED_BYTES:
                    raise UpdateError("The expanded update package is unexpectedly large.")
            if "blender_manifest.toml" not in names or "__init__.py" not in names:
                raise UpdateError("The release is not a Nova3D Blender extension package.")
            manifest_info = archive.getinfo("blender_manifest.toml")
            if manifest_info.file_size > 128 * 1024:
                raise UpdateError("The update manifest is invalid.")
            try:
                manifest_text = archive.read(manifest_info).decode("utf-8")
            except (UnicodeDecodeError, RuntimeError):
                raise UpdateError("The update manifest could not be read.") from None
    except UpdateError:
        raise
    except (OSError, zipfile.BadZipFile, KeyError) as exc:
        raise UpdateError(f"The update package is not a valid ZIP file: {exc}") from None

    fields = dict(_MANIFEST_FIELD_RE.findall(manifest_text))
    if fields.get("id") != constants.ADDON_PACKAGE_ID:
        raise UpdateError("The downloaded package is not the Nova3D add-on.")
    if fields.get("version") != expected_version:
        raise UpdateError("The downloaded package version does not match its release.")
    if fields.get("type") != "add-on":
        raise UpdateError("The downloaded package is not a Blender add-on.")
    return fields


def _safe_member(info):
    name = info.filename
    if not name or "\\" in name or "\x00" in name:
        return False
    path = PurePosixPath(name)
    if (path.is_absolute() or ".." in path.parts or "." in path.parts
            or any(":" in part for part in path.parts)):
        return False
    if info.flag_bits & 0x1:  # encrypted members are not valid extension files
        return False
    mode = (info.external_attr >> 16) & 0o170000
    return mode != stat.S_IFLNK


def make_legacy_archive(extension_path, *, expected_version):
    """Wrap a manifest-root extension ZIP for Blender 3.6–4.1 installation.

    Blender 4.2+ expects ``blender_manifest.toml`` at the archive root.  The
    legacy installer instead expects one top-level Python package directory.
    Repacking the already validated files provides both layouts without asking
    release engineering to publish two different code archives.
    """
    validate_release_archive(extension_path, expected_version=expected_version)
    base_dir = os.path.dirname(extension_path)
    destination = os.path.join(
        base_dir,
        f"{constants.ADDON_PACKAGE_ID}-{expected_version}-legacy.zip",
    )
    partial = destination + ".part"
    try:
        with zipfile.ZipFile(extension_path) as source, zipfile.ZipFile(
                partial, "w", zipfile.ZIP_DEFLATED) as target:
            for info in source.infolist():
                # The source was validated immediately above. Preserve bytes but
                # normalize every member beneath the one legacy package folder.
                if info.is_dir():
                    continue
                target_info = zipfile.ZipInfo(
                    f"{constants.ADDON_PACKAGE_ID}/{info.filename}",
                    date_time=info.date_time,
                )
                target_info.compress_type = zipfile.ZIP_DEFLATED
                target_info.external_attr = info.external_attr
                with source.open(info) as source_file, target.open(
                        target_info, "w") as target_file:
                    shutil.copyfileobj(source_file, target_file, length=1 << 16)
        os.replace(partial, destination)
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        _remove_if_exists(partial)
        raise UpdateError(f"Could not prepare the Blender 3.6 update: {exc}") from None
    return destination


def install_archive_for_blender(extension_path, *, expected_version, blender_version):
    """Return the proper package layout for the running Blender generation."""
    if tuple(blender_version) >= (4, 2, 0):
        return extension_path
    return make_legacy_archive(extension_path, expected_version=expected_version)


def extension_repo_from_package(package_name):
    """Return the extension repository module from ``bl_ext.<repo>...``."""
    parts = (package_name or "").split(".")
    if len(parts) >= 3 and parts[0] == "bl_ext":
        return parts[1]
    return ""


def _remove_if_exists(path):
    try:
        if os.path.exists(path):
            os.unlink(path)
    except OSError:
        pass
