# SPDX-License-Identifier: MIT
"""Direct Anthropic/OpenAI credential and model-access preflight.

The Blender add-on has no third-party dependencies, so these checks use the
standard library. A check deliberately does two things:

1. list models to confirm the key can see the exact Nova3D model; and
2. make one tiny request to prove the provider will actually serve it now.

The second step catches invalid keys, disabled model access, and many provider
billing/spend-limit failures before Nova3D starts a multi-minute workflow.
Ordinary API keys do not expose a trustworthy dollar balance, so the UI simply
reminds users to keep enough provider balance for the run to finish.

Provider keys are never logged or included in exceptions. They are fingerprinted
only to invalidate a prior successful check when the stored key changes.
"""

from dataclasses import dataclass
import hashlib
import json
import ssl
import urllib.error
import urllib.request

from .. import constants


_SSL_CONTEXT = ssl.create_default_context()
_TIMEOUT_SECONDS = 45.0
_ANTHROPIC_API = "https://api.anthropic.com/v1"
_OPENAI_API = "https://api.openai.com/v1"


class ProviderAccessError(Exception):
    """A safe, classified error from a direct provider preflight."""

    def __init__(self, message, *, provider, category, status=None, code=None):
        super().__init__(message)
        self.message = message
        self.provider = provider
        self.category = category
        self.status = status
        self.code = code

    def __str__(self):
        return self.message


@dataclass(frozen=True)
class ProviderValidation:
    provider: str
    available_model_ids: tuple
    checked_model_id: str


def provider_label(provider):
    if provider == constants.PROVIDER_ANTHROPIC:
        return "Anthropic"
    if provider == constants.PROVIDER_OPENAI:
        return "OpenAI"
    return "Model provider"


def key_fingerprint(api_key):
    key = (api_key or "").strip().encode("utf-8")
    return hashlib.sha256(key).hexdigest()[:24] if key else ""


def provider_key(prefs, provider):
    if provider == constants.PROVIDER_ANTHROPIC:
        return (getattr(prefs, "anthropic_api_key", "") or "").strip()
    if provider == constants.PROVIDER_OPENAI:
        return (getattr(prefs, "openai_api_key", "") or "").strip()
    return ""


def validation_is_current(prefs, provider):
    key = provider_key(prefs, provider)
    if not key:
        return False
    attr = ("anthropic_validation_fingerprint"
            if provider == constants.PROVIDER_ANTHROPIC
            else "openai_validation_fingerprint")
    return getattr(prefs, attr, "") == key_fingerprint(key)


def validated_model_ids(prefs, provider):
    if not validation_is_current(prefs, provider):
        return ()
    attr = ("anthropic_available_models" if provider == constants.PROVIDER_ANTHROPIC
            else "openai_available_models")
    return tuple(part for part in (getattr(prefs, attr, "") or "").split(",") if part)


def available_provider_options(prefs):
    """Return only provider-key options whose exact models were validated."""
    if prefs is None:
        return ()
    available = {
        provider: set(validated_model_ids(prefs, provider))
        for provider in (constants.PROVIDER_ANTHROPIC, constants.PROVIDER_OPENAI)
    }
    return tuple(
        option for option in constants.PROVIDER_MODEL_OPTIONS
        if constants.provider_model_id_for_option(option)
        in available.get(constants.provider_for_option(option), set())
    )


def validate_provider(provider, api_key, candidate_model_ids=None):
    """Validate a key and return accessible Nova3D models.

    ``candidate_model_ids`` defaults to every direct model Nova3D exposes for
    the provider. At least one tiny inference is performed.
    """
    key = (api_key or "").strip()
    if not key:
        raise ProviderAccessError(
            f"Enter an {provider_label(provider)} API key first.",
            provider=provider, category="missing_key")

    candidates = tuple(candidate_model_ids or (
        constants.provider_model_id_for_option(option)
        for option in constants.provider_options(provider)
    ))
    candidates = tuple(model_id for model_id in candidates if model_id)
    if not candidates:
        raise ProviderAccessError(
            "Nova3D has no models configured for this provider.",
            provider=provider, category="configuration")

    if provider == constants.PROVIDER_ANTHROPIC:
        visible = _visible_or_candidates(
            provider, candidates, lambda: _list_anthropic_models(key))
        listed = tuple(model_id for model_id in candidates if model_id in visible)
        _require_available(provider, candidates, listed)
        available = _probe_available_models(
            provider, listed, lambda model_id: _probe_anthropic(key, model_id))
    elif provider == constants.PROVIDER_OPENAI:
        visible = _visible_or_candidates(
            provider, candidates, lambda: _list_openai_models(key))
        listed = tuple(model_id for model_id in candidates if model_id in visible)
        _require_available(provider, candidates, listed)
        available = _probe_available_models(
            provider, listed, lambda model_id: _probe_openai(key, model_id))
    else:
        raise ProviderAccessError(
            "This provider is not supported by Nova3D.",
            provider=provider, category="configuration")

    return ProviderValidation(provider, available, available[0])


def validate_selected_model(provider, api_key, model_id):
    """Strong preflight for the exact model selected immediately before a run."""
    result = validate_provider(provider, api_key, (model_id,))
    return result


def _require_available(provider, requested, available):
    if available:
        return
    names = ", ".join(requested)
    label = provider_label(provider)
    extra = (" Enable the model in your OpenAI project limits, then test again."
             if provider == constants.PROVIDER_OPENAI
             else " Check that this workspace can use Claude Fable 5.")
    raise ProviderAccessError(
        f"Your {label} key is valid, but it cannot access {names}.{extra}",
        provider=provider, category="model_access")


def _visible_or_candidates(provider, candidates, list_models):
    try:
        return list_models()
    except ProviderAccessError as exc:
        # A restricted project key can be allowed to call a model while lacking
        # permission to enumerate /models. In that one case, the real tiny
        # inference below remains the authoritative access test.
        if exc.category == "model_access":
            return set(candidates)
        raise


def _probe_available_models(provider, model_ids, probe):
    accessible = []
    last_access_error = None
    for model_id in model_ids:
        try:
            probe(model_id)
            accessible.append(model_id)
        except ProviderAccessError as exc:
            if exc.category == "model_access":
                last_access_error = exc
                continue
            raise
    if accessible:
        return tuple(accessible)
    if last_access_error is not None:
        raise last_access_error
    _require_available(provider, model_ids, ())
    return ()


def _list_anthropic_models(key):
    data = _request_json(
        "GET", f"{_ANTHROPIC_API}/models?limit=1000",
        provider=constants.PROVIDER_ANTHROPIC,
        headers={"x-api-key": key, "anthropic-version": "2023-06-01"},
    )
    rows = data.get("data") if isinstance(data, dict) else None
    return {row.get("id") for row in (rows or []) if isinstance(row, dict) and row.get("id")}


def _probe_anthropic(key, model_id):
    _request_json(
        "POST", f"{_ANTHROPIC_API}/messages",
        provider=constants.PROVIDER_ANTHROPIC,
        headers={"x-api-key": key, "anthropic-version": "2023-06-01"},
        body={
            "model": model_id,
            "max_tokens": 16,
            "messages": [{"role": "user", "content": "Reply with OK."}],
        },
    )


def _list_openai_models(key):
    data = _request_json(
        "GET", f"{_OPENAI_API}/models",
        provider=constants.PROVIDER_OPENAI,
        headers={"Authorization": f"Bearer {key}"},
    )
    rows = data.get("data") if isinstance(data, dict) else None
    return {row.get("id") for row in (rows or []) if isinstance(row, dict) and row.get("id")}


def _probe_openai(key, model_id):
    # Match Nova3D_toolkit's direct OpenAI adapter (Chat Completions) rather
    # than testing a different endpoint that could have different permissions.
    _request_json(
        "POST", f"{_OPENAI_API}/chat/completions",
        provider=constants.PROVIDER_OPENAI,
        headers={"Authorization": f"Bearer {key}"},
        body={
            "model": model_id,
            "messages": [{"role": "user", "content": "Reply with OK."}],
            "max_completion_tokens": 32,
        },
    )


def _request_json(method, url, *, provider, headers=None, body=None):
    merged = {"Accept": "application/json", "Content-Type": "application/json"}
    if headers:
        merged.update(headers)
    encoded = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=encoded, headers=merged, method=method)
    try:
        with urllib.request.urlopen(
                request, timeout=_TIMEOUT_SECONDS, context=_SSL_CONTEXT) as response:
            raw = response.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read() if hasattr(exc, "read") else b""
        code, message = _provider_error(raw)
        raise _classified_error(provider, exc.code, code, message) from None
    except urllib.error.URLError as exc:
        reason = getattr(exc, "reason", None) or "network unavailable"
        raise ProviderAccessError(
            f"Could not reach {provider_label(provider)} ({reason}). Your key was not rejected; check your connection and try again.",
            provider=provider, category="network") from None
    except (TimeoutError, ssl.SSLError):
        raise ProviderAccessError(
            f"{provider_label(provider)} did not answer the access check. Your key was not rejected; try again.",
            provider=provider, category="network") from None


def _provider_error(raw):
    try:
        data = json.loads((raw or b"").decode("utf-8"))
    except Exception:
        return None, ""
    error = data.get("error") if isinstance(data, dict) else None
    if isinstance(error, dict):
        return error.get("code") or error.get("type"), str(error.get("message") or "")
    if isinstance(data, dict):
        return data.get("code"), str(data.get("message") or "")
    return None, ""


def _classified_error(provider, status, code, raw_message):
    label = provider_label(provider)
    code_text = str(code or "").lower()
    message_text = str(raw_message or "").lower()
    combined = f"{code_text} {message_text}"

    if status == 401 or "authentication" in combined or "invalid_api_key" in combined:
        return ProviderAccessError(
            f"{label} rejected this API key. Check it or create a new key on {label}.",
            provider=provider, category="invalid_key", status=status, code=code)
    if any(term in combined for term in (
            "credit_balance", "insufficient_quota", "billing", "payment",
            "spend_limit", "usage_limit", "balance")):
        return ProviderAccessError(
            f"{label} could not start usage. Check your API balance and spending limits, then try again.",
            provider=provider, category="billing", status=status, code=code)
    if status in (403, 404) or any(term in combined for term in (
            "model_not_found", "permission", "not have access", "data retention",
            "workspace")):
        suffix = (" Enable the selected model in OpenAI project limits."
                  if provider == constants.PROVIDER_OPENAI
                  else " Check Claude Fable 5 access for this workspace.")
        return ProviderAccessError(
            f"{label} accepted the key, but the selected model is not enabled.{suffix}",
            provider=provider, category="model_access", status=status, code=code)
    if status == 429:
        return ProviderAccessError(
            f"{label} rate-limited the access check. Wait briefly and test again; no Nova3D workflow was started.",
            provider=provider, category="rate_limit", status=status, code=code)
    if status is not None and status >= 500:
        return ProviderAccessError(
            f"{label} is temporarily unavailable. Your key was not rejected; try again shortly.",
            provider=provider, category="provider_unavailable", status=status, code=code)
    return ProviderAccessError(
        f"{label} could not use this key with the selected model. Check provider billing, permissions, and model access.",
        provider=provider, category="provider_error", status=status, code=code)
