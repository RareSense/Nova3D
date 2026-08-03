# SPDX-License-Identifier: MIT
"""Check GitHub Releases for a newer add-on build.

Read-only and unauthenticated: it asks the public GitHub API which
``blender-plugin-v*`` release is newest and compares it to the installed
version. No credential is sent and nothing is downloaded or installed — the
add-on only *tells* the user an update exists and links them to the page.

Pure module (no `bpy`); the blocking HTTP call must run on a worker thread.
"""

import re

from .. import constants
from ..api import http

_VERSION_RE = re.compile(r"(\d+)\.(\d+)\.(\d+)")


def parse_version(text):
    """Extract a ``(major, minor, patch)`` tuple from a tag/version string.

    Tolerates the ``blender-plugin-v`` / ``v`` prefixes. Returns None if no
    dotted version is present.
    """
    match = _VERSION_RE.search(text or "")
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def is_newer(latest, current):
    """True when *latest* is a strictly higher version tuple than *current*."""
    return bool(latest) and bool(current) and latest > current


def fetch_latest(*, api_url=None, tag_prefix=None, timeout=None):
    """Return ``(version_tuple, version_str, html_url)`` for the newest matching
    release, or None if none is found.

    GitHub returns releases newest-first, so the first published (non-draft,
    non-prerelease) entry whose tag matches ``tag_prefix`` is the latest.
    """
    api_url = api_url or constants.GITHUB_RELEASES_API
    tag_prefix = tag_prefix if tag_prefix is not None else constants.RELEASE_TAG_PREFIX
    timeout = timeout or constants.UPDATE_HTTP_TIMEOUT

    # GitHub requires a User-Agent; be explicit rather than relying on urllib's.
    releases = http.request_json(
        "GET", api_url, headers={"User-Agent": "nova3d-blender-addon"}, timeout=timeout,
    )
    if not isinstance(releases, list):
        return None

    for release in releases:
        if not isinstance(release, dict):
            continue
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = release.get("tag_name") or ""
        if tag_prefix and not tag.startswith(tag_prefix):
            continue
        version = parse_version(tag)
        if version:
            html_url = release.get("html_url") or constants.RELEASES_PAGE_URL
            return version, ".".join(str(part) for part in version), html_url
    return None
