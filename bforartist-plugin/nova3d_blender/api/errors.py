# SPDX-License-Identifier: MIT
"""Error types and user-facing message mapping for API failures.

`ApiError` carries the HTTP status, the backend `code`/`category` (when present),
and a human-readable message. `friendly_message` turns the backend's
`error_category` taxonomy into the same wording the web client shows, so a user
sees identical guidance whether they generated in Blender or in the browser.
"""


class ApiError(Exception):
    """A failed API call. `message` is always safe to show to the user."""

    def __init__(self, message, *, status=None, code=None, category=None,
                 retryable=False):
        super().__init__(message)
        self.message = message
        self.status = status
        self.code = code
        self.category = category
        self.retryable = retryable

    def __str__(self):
        return self.message


class AuthError(ApiError):
    """401/expired/revoked key — the user must fix their API key."""


class ServiceUnavailableError(ApiError):
    """Nova3D could not be reached, or answered with a 5xx.

    Signals a problem on the network/server side (outage, gateway, no
    connection) rather than anything the user did — so the UI can say "the
    service is unreachable, retry later" instead of blaming their API key.
    Still an `ApiError`, so existing `status`-based retry logic is unaffected.
    """


# Maps the backend `error_category` values (see GraphFlow's failure taxonomy)
# to friendly copy. Mirrors CadResult._messageForCategory in the web client.
_CATEGORY_MESSAGES = {
    "invalid_api_key":
        "The provider rejected this request's API key. "
        "Check your Nova3D API key in the add-on preferences.",
    "missing_api_key":
        "A required provider key is missing on the server side. "
        "Try another model or contact support.",
    "model_access_denied":
        "This account cannot use the selected model. Choose another model.",
    "unsupported_provider_for_model":
        "The selected model is not available right now. Choose another model.",
    "insufficient_credits":
        "Not enough credits for this generation. Buy more credits and retry.",
    "quota_or_rate_limit":
        "The provider hit a quota or rate limit. Wait a moment and retry.",
    "provider_unavailable":
        "The model provider is temporarily unavailable. Retry shortly.",
    "api_timeout":
        "The provider timed out while generating. Retry shortly.",
    "blender_generation_failed":
        "The generated 3D script could not produce a valid model after "
        "automatic repair attempts. Try rephrasing the prompt.",
    "artifact_upload_failed":
        "The model was generated but the download could not be prepared. Retry.",
    "generation_timeout":
        "Generation took longer than expected. It may still finish; check your "
        "web history before retrying.",
}


def friendly_message(category, fallback="Generation failed. Try again."):
    """Return user-facing copy for a backend `error_category`."""
    if not category:
        return fallback
    return _CATEGORY_MESSAGES.get(category, fallback)
