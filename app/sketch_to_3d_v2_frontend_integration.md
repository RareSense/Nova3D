# sketch_to_3d_v2 and sketch_to_3d_byok_v2 Frontend Integration Sheet

This document describes how the Nova3D Flutter web client integrates with the
GraphFlow `sketch_to_3d_v2` and `sketch_to_3d_byok_v2` initial generation
workflows. It is written from the frontend point of view, but uses the GraphFlow
workflow contract as the ground truth for request, progress, result, and failure
handling.

No client code is required to understand this sheet. Source files referenced
below are the current implementation points.

## Scope

`sketch_to_3d_v2` is the paid-credit initial generation workflow.
`sketch_to_3d_byok_v2` is the provider-key initial generation workflow. The two
workflows share the same v2 status/result shape, but differ in billing and key
payload fields.

Current behavior:

- Paid-credit model options use `sketch_to_3d_v2`.
- BYOK model options use `sketch_to_3d_byok_v2`.
- Edit workflows such as regenerate, add part, and articulation use separate
  GraphFlow workflows.
- Legacy `sketch_to_3d` is retained as a constant for compatibility, but it is
  not selected for initial BYOK generation by the current client.
- BYOK generation is zero Nova3D credits. The client does not run the Nova3D
  credit estimate/balance preflight for BYOK options.

Important frontend source files:

| Area | File |
|---|---|
| Base URLs and workflow constants | `lib/core/constants.dart` |
| GraphFlow HTTP calls | `lib/features/cad/data/cad_service.dart` |
| Model option mapping | `lib/features/cad/models/generation_model_option.dart` |
| Request image and prompt model | `lib/features/cad/models/generation_request.dart` |
| Reference image processing | `lib/features/cad/utils/reference_image_processor.dart` |
| Prompt word-limit guard | `lib/features/cad/utils/generation_prompt_limits.dart` |
| Status/result parsing | `lib/features/cad/models/cad_models.dart` |
| Home page preflight | `lib/features/home/presentation/home_page.dart` |
| Chat generation lifecycle | `lib/features/chat/state/chat_provider.dart` |
| Credit wallet calls | `lib/features/subscription/data/billing_service.dart` |

## Runtime Topology

The browser does not call toolkit tools directly. It talks to the configured
GraphFlow API, and GraphFlow invokes the toolkit tools.

```text
Flutter web app
  -> Auth service
  -> GraphFlow compute API
  -> GraphFlow sketch_to_3d_v2 or sketch_to_3d_byok_v2 runtime
  -> Nova3D_toolkit tools
  -> artifact storage URLs
  -> Flutter chat and model viewer
```

Frontend base URL constants:

| Constant | Dart define | Default | Used for |
|---|---|---|---|
| `kAuthBaseUrl` | `AUTH_BASE_URL` | `https://nova3d.xyz` | sign-in/session |
| `kApiBaseUrl` | `API_BASE_URL` | `https://nova3d.xyz/api` | chat, account API keys, wallet |
| `kCadBaseUrl` | `CAD_BASE_URL` | `https://nova3d.xyz/api` | GraphFlow generation calls |
| `_billingBaseUrl` | `BILLING_BASE_URL` | `https://nova3d.xyz` | hosted billing checkout |

For self-hosting, set all URLs that your deployment splits across services.
For example:

```bash
flutter run -d web-server --web-port 5555 \
  --dart-define=AUTH_BASE_URL=https://your-auth.example.com \
  --dart-define=API_BASE_URL=https://your-api.example.com/api \
  --dart-define=CAD_BASE_URL=https://your-api.example.com/api \
  --dart-define=BILLING_BASE_URL=https://your-billing.example.com
```

For a static web build, pass the same `--dart-define` values to
`flutter build web`.

## Workflow Constants

The client currently defines:

```dart
const String kSketchTo3dWorkflow = 'sketch_to_3d';
const String kSketchTo3dPaidWorkflow = 'sketch_to_3d_v2';
const String kSketchTo3dByokWorkflow = 'sketch_to_3d_byok_v2';
```

`CadService.startGeneration()` chooses the workflow as follows:

- If the selected model option has a `workflowName`, use that.
- Otherwise, if the model is paid-credit, use `sketch_to_3d_v2`.
- Otherwise, use `sketch_to_3d_byok_v2`.

All paid-credit options explicitly set `workflowName: 'sketch_to_3d_v2'`.
All BYOK options explicitly set `workflowName: 'sketch_to_3d_byok_v2'`.

## Paid Model Mapping

Paid model options are declared in
`lib/features/cad/models/generation_model_option.dart`.

| Option id | UI label | Workflow | Code LLM profile | Code LLM tier | Credits shown |
|---|---|---|---|---|---|
| `credits_claude_opus_4_8_anthropic` | Claude Opus 4.8 | `sketch_to_3d_v2` | `nova3d_code_generation` | `claude_opus_4_8_anthropic` | 25 |
| `credits_claude_sonnet_4_6_anthropic` | Claude Sonnet 4.6 | `sketch_to_3d_v2` | `nova3d_code_generation` | `claude_sonnet_4_6_anthropic` | 15 |
| `credits_gpt_5_5_openrouter` | GPT-5.5 | `sketch_to_3d_v2` | `nova3d_code_generation` | `gpt_5_5_openrouter` | 28 |
| `credits_gemini_3_1_pro_google` | Gemini 3.1 Pro Preview | `sketch_to_3d_v2` | `nova3d_code_generation` | `gemini_3_1_pro_google` | 12 |

`credits_gemini_3_1_pro_google` is the default paid option when available.

Paid `sketch_to_3d_v2` payloads do not include provider API keys. The code
comment in `CadService` says this is intentional: provider credentials are
resolved server-side by the toolkit/GraphFlow deployment.

## BYOK Model Mapping

BYOK model options are declared in
`lib/features/cad/models/generation_model_option.dart`. They are shown only when
the user has saved a non-empty API key for the corresponding provider.

| Option id | UI label | Key provider | Workflow | Code LLM profile | Code LLM tier |
|---|---|---|---|---|---|
| `anthropic_claude_sonnet` | Claude Sonnet 4.6 | Anthropic | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `claude_sonnet_4_6_anthropic` |
| `anthropic_claude_opus_4_8` | Claude Opus 4.8 | Anthropic | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `claude_opus_4_8_anthropic` |
| `openai_gpt55` | GPT-5.5 | OpenAI | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `gpt_5_5_openai` |
| `openrouter_gpt55` | GPT-5.5 | OpenRouter | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `gpt_5_5_openrouter` |
| `openrouter_gemini` | Gemini 3.1 Pro Preview | OpenRouter | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `gemini_3_1_pro_openrouter` |
| `openrouter_claude_sonnet` | Claude Sonnet 4.6 | OpenRouter | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `claude_sonnet_4_6_openrouter` |
| `openrouter_claude_opus` | Claude Opus 4.8 | OpenRouter | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `claude_opus_4_8_openrouter` |
| `gemini_gemini` | Gemini 3.1 Pro Preview | Gemini | `sketch_to_3d_byok_v2` | `nova3d_code_generation` | `gemini_3_1_pro_google` |

Anthropic is intentionally limited to Sonnet and Opus 4.8 for both direct
Anthropic and OpenRouter-routed Claude options.

BYOK `sketch_to_3d_byok_v2` payloads include the user's saved provider key in
`code_llm_api_key`. They do not include Nova3D credit pricing context beyond the
same `code_llm_profile` and `code_llm_tier` fields used for model routing.


## Auth Contract

All GraphFlow generation calls use:

```http
Authorization: Bearer <auth token>
Content-Type: application/json
```

If no token exists, the client fails locally with `Please sign in again.`.

If GraphFlow responds with 401, the client shows either:

- `Your session expired. Please sign in again.`
- `GraphFlow rejected the current sign-in token. Please sign out and sign in again.`

## Preflight Endpoints

### Readiness

```http
GET /workflow/readiness/{workflowName}
```

For paid initial generation, `{workflowName}` is `sketch_to_3d_v2`.
For BYOK initial generation, `{workflowName}` is `sketch_to_3d_byok_v2`.

Expected response fields used by the frontend:

```json
{
  "ready": true,
  "reason": null,
  "projected_cost": 0,
  "authorized_budget": 0
}
```

Frontend behavior:

- If `ready == true`, continue.
- If `reason == "generation_service_unavailable"`, show a generation service
  unavailable message.
- Otherwise show `Generation is not available right now.`

### Credit Estimate

Paid-credit models call:

```http
POST /credits/estimate
```

Request body:

```json
{
  "workflow_name": "sketch_to_3d_v2",
  "num_variations": 1,
  "pricing_context": {
    "code_llm_profile": "nova3d_code_generation",
    "code_llm_tier": "gemini_3_1_pro_google"
  }
}
```

Response fields used by the frontend:

```json
{
  "projected_max_hold": 12,
  "authorized_budget": 12
}
```

The client then calls `GET /credits/balance/me` through `API_BASE_URL` and
requires `available >= authorized_budget`. If the wallet cannot be confirmed or
is too low, generation is blocked before `/run/state/sketch_to_3d_v2`.

BYOK models do not call `/credits/estimate` and do not call
`GET /credits/balance/me` for initial generation. The required preflight is
workflow readiness plus the local saved-key check. If no local key exists for
the selected provider, the client fails before start with:

```text
Add a {Provider} key in Settings.
```

## Paid Start Endpoint

```http
POST /run/state/sketch_to_3d_v2?request_id={workflowId}
```

Body shape used by the current frontend:

```json
{
  "payload": {
    "prompt": "trimmed user prompt",
    "code_llm_profile": "nova3d_code_generation",
    "code_llm_tier": "gemini_3_1_pro_google",
    "has_reference_images": true,
    "image_artifact": [
      "data:image/png;base64,...",
      "data:image/png;base64,..."
    ]
  },
  "return_nodes": [
    "final_validated_correction",
    "final_latest_valid",
    "fail_generation"
  ],
  "conversation": {
    "conversation_id": "conversation id",
    "relation_type": "initial_generation",
    "link_metadata": {
      "operation": "sketch_to_3d_v2",
      "client": "flutter"
    }
  }
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `prompt` | yes, unless image-only request | Trimmed prompt text. |
| `code_llm_profile` | yes for paid model routing | Defaults client-side to `nova3d_code_generation`. |
| `code_llm_tier` | yes for paid model routing | Comes from selected paid model option. |

Optional image fields:

| Field | When sent | Notes |
|---|---|---|
| `has_reference_images` | image attached | Set to `true`. |
| `image_artifact` | image attached | List of full browser data URLs. |

Fields intentionally not sent on paid `sketch_to_3d_v2`:

- `api_key`
- `provider`
- `llm`
- `code_llm_api_key`
- `validate`

Those belong to provider-key flows, not the paid v2 path.

## BYOK Start Endpoint

```http
POST /run/state/sketch_to_3d_byok_v2?request_id={workflowId}
```

Body shape used by the current frontend:

```json
{
  "payload": {
    "prompt": "trimmed user prompt",
    "code_llm_profile": "nova3d_code_generation",
    "code_llm_tier": "claude_opus_4_8_openrouter",
    "code_llm_provider": "openrouter",
    "code_llm_api_key": "user saved provider key",
    "has_reference_images": true,
    "image_artifact": [
      "data:image/png;base64,...",
      "data:image/png;base64,..."
    ]
  },
  "return_nodes": [
    "final_validated_correction",
    "final_latest_valid",
    "fail_generation",
    "require_byok_api_key"
  ],
  "conversation": {
    "conversation_id": "conversation id",
    "relation_type": "initial_generation",
    "link_metadata": {
      "operation": "sketch_to_3d_byok_v2",
      "client": "flutter"
    }
  }
}
```

Required BYOK payload fields:

| Field | Required | Notes |
|---|---:|---|
| `prompt` | yes, unless image-only request | Trimmed prompt text. |
| `code_llm_profile` | yes | Defaults client-side to `nova3d_code_generation`. |
| `code_llm_tier` | yes | Comes from the selected BYOK model option. |
| `code_llm_provider` | yes | `anthropic`, `openai`, `openrouter`, or `gemini`. |
| `code_llm_api_key` | yes | Loaded from the user's saved API keys for the selected provider. |

Fields intentionally not sent on BYOK `sketch_to_3d_byok_v2`:

- Nova3D credit estimate/balance payloads.
- Legacy `api_key`, `provider`, `llm`, and `validate` fields.
- `reference_image_artifact`; the v2 payload uses `image_artifact`.

## Image Handling

The home page and chat input accept image files via `file_picker`.

Frontend rules:

- Max selected images per generation request is 3.
- Max source file size is `8 MB` before resize.
- If an image has a width or height greater than 512 pixels, the client resizes
  it so the longest side is 512 pixels while preserving aspect ratio.
- Resized images are encoded as PNG.
- The image is converted to a browser data URL:
  `data:{mime};base64,{bytes}`.
- MIME is based on the file extension via `mimeTypeForExtension()` unless the
  image was resized, in which case MIME is PNG.
- Paid v2 and BYOK v2 both send the data URLs as a list in `image_artifact`.

The toolkit prompt builder accepts `image_artifact` as either one artifact ref
or a list of artifact refs. GraphFlow's artifact normalizer recursively converts
data URLs inside lists into artifact references before tools consume them.

## Prompt Guard

The client limits initial generation prompt text to 40 words. The guard exists
in both home-page generation and chat input generation. Image-only requests are
allowed.

This 40-word limit is a client rule. The backend/toolkit currently has broader
prompt-builder limits rather than this exact word cap.

## GraphFlow Tool Chain

GraphFlow details that matter to the frontend:

- Runtime max elapsed time is 7200 seconds.


## LLM Routing Inside v2

For paid `sketch_to_3d_v2`, the client only sends:

```json
{
  "code_llm_profile": "nova3d_code_generation",
  "code_llm_tier": "selected tier"
}
```

For BYOK `sketch_to_3d_byok_v2`, the client sends the same routing fields plus
the selected provider and the user's saved key:

```json
{
  "code_llm_profile": "nova3d_code_generation",
  "code_llm_tier": "selected tier",
  "code_llm_provider": "selected provider",
  "code_llm_api_key": "user saved provider key"
}
```

BYOK captioning, code generation, and validation are expected to use the same
selected model routing because the frontend sends only one model tier/provider
pair for the v2 workflow.


## Status Polling

The client polls:

```http
GET /status/{workflowId}
```

Polling interval:

```text
3 seconds
```

Status parser inputs:

- `runtime.state`
- `runtime.last_exit_node_id`
- `node_visit_seq` keys, using the last visited key as the current node

Terminal states:

- `completed`
- `succeeded`
- `success`
- `budget_exhausted`
- `failed`
- `terminated`
- `cancelled`
- `timed_out`
- `timeout`

Terminal nodes recognized by the frontend:

- `final_latest_valid`
- `final_validated_correction`
- `fail_generation`
- `require_byok_api_key`
- legacy terminal nodes retained for compatibility

Progress labels shown by the frontend:

| Node | User-facing label |
|---|---|
| `caption_prompt` | Reading your reference image... |
| `caption_llm` | Understanding the reference image... |
| `generation_prompt` | Preparing the 3D generation prompt... |
| `code_generation_llm` | Writing the Blender scene... |
| `run_blender` | Building and exporting the 3D model... |
| `blender_retry_gate` | Checking the generated model... |
| `build_repair_prompt` | Preparing an automatic repair... |
| `repair_llm` | Repairing the Blender script... |
| `capture_validation_screenshots` | Capturing validation views... |
| `validation_prompt` | Preparing model validation... |
| `validation_llm` | Reviewing the generated model... |
| `validation_result_parser` | Finalizing the model... |
| `validation_correction_blender` | Applying validation fixes... |
| `final_latest_valid` | Finalizing the model... |
| `final_validated_correction` | Finalizing the corrected model... |
| `fail_generation` | Generation failed. |
| `require_byok_api_key` | Checking provider key... |

Recoverable polling errors:

- 404
- workflow not found
- service unavailable
- still starting
- timeout
- 502, 503, 504

Auth/token errors and budget exhaustion are not treated as recoverable.

## Result Endpoint

After terminal status, the client calls:

```http
GET /result/{workflowId}
```

The result receive timeout is 5 minutes.

The frontend searches result node keys in this order:

```text
final_validated_correction
final_latest_valid
sketch_to_3d_generator
regenerate_3d_part
add_3d_part
articulate_3d_model
fail_generation
require_byok_api_key
```

For v2 success, the expected result carrier is one of:

- `final_validated_correction`
- `final_latest_valid`

For v2 failure, the expected result carrier is one of:

- `fail_generation`
- `require_byok_api_key`

The client accepts either a direct payload object or a wrapper with `result`.

## Success Result Contract

The client extracts the model URL in this order:

1. `model_url`
2. `model.url`
3. `model_artifact.url`
4. `glb_artifact.url`

The client extracts the model artifact in this order:

1. `model_artifact`
2. `model`
3. `glb_artifact`

The client extracts the code artifact in this order:

1. `code_artifact`
2. `source_code_artifact`
3. `input_code_artifact`

For `sketch_to_3d_v2` and `sketch_to_3d_byok_v2`, GraphFlow terminal maps
provide:

`final_latest_valid`:

```json
{
  "status": "validation_result_parser.status",
  "ok": "validation_result_parser.ok",
  "action": "validation_result_parser.action",
  "message": "validation_result_parser.message",
  "reason": "validation_result_parser.reason",
  "glb_artifact": "validation_result_parser.latest_valid_glb_artifact",
  "model_artifact": "validation_result_parser.model_artifact",
  "code_artifact": "validation_result_parser.latest_valid_code_artifact",
  "validation_decision": "validation_result_parser",
  "validation_llm": "validation_llm"
}
```

`final_validated_correction`:

```json
{
  "status": "validation_correction_blender.status",
  "ok": "validation_correction_blender.ok",
  "glb_artifact": "validation_correction_blender.glb_artifact",
  "model_artifact": "validation_correction_blender.glb_artifact",
  "code_artifact": "validation_correction_blender.code_artifact",
  "validation_decision": "validation_result_parser",
  "validation_llm": "validation_llm",
  "validation_correction_blender": "validation_correction_blender"
}
```

Once a GLB URL is found, the chat message is finalized as:

```text
Your 3D model is ready.
```

The final message stores:

- `modelUrl`
- `workflowId`
- `modelArtifact`
- `codeArtifact`
- `jointsArtifact`, if present
- `joints`, if present
- `operation: initial_generation`
- `sourceModelUrl`
- `modelOptionId`
- `modelLabel`
- `instructionPrompt`

## Failure Result Contract

GraphFlow `fail_generation` maps:

```json
{
  "user_message": "blender_retry_gate.user_message",
  "reason": "blender_retry_gate.reason",
  "error_category": "blender_retry_gate.error_category",
  "failure_origin": "blender_retry_gate.failure_origin",
  "diagnostics": "blender_retry_gate.diagnostics"
}
```

GraphFlow `require_byok_api_key` can be returned by BYOK v2 when the workflow
cannot proceed because the provider key is missing or rejected. The frontend
parses it through the same failure-result path and keeps backend/tool messages
when present.

The frontend marks a result as failed when no GLB URL exists and any failure
signal exists, including:

- root `state` is failed/failure
- `runtime.state` is failed/failure/budget_exhausted
- payload `status == failed`
- payload `action == error`
- payload `ok == false`
- payload includes `failure`
- payload includes `error_category`
- payload includes `user_message`

The frontend chooses the user-visible failure message from:

1. `failure.user_message`
2. `failure.message`
3. `user_message`
4. `message`
5. `detail`
6. `error`
7. a frontend fallback based on `error_category`

Known category fallbacks:

| Category | Frontend message behavior |
|---|---|
| `invalid_api_key` | Provider rejected the API key. |
| `missing_api_key` | Provider is missing an API key. |
| `model_access_denied` | Key cannot use the selected model. |
| `unsupported_provider_for_model` | Provider/model pair is incompatible. |
| `insufficient_credits` | Provider lacks credits or balance. |
| `quota_or_rate_limit` | Provider quota/rate limit reached. |
| `provider_unavailable` | Provider temporarily unavailable or overloaded. |
| `api_timeout` | Provider timed out. |
| `blender_generation_failed` | Blender script could not produce a valid model after repairs. |
| `artifact_upload_failed` | Model generated but artifact preparation failed. |
| `generation_timeout` | Generation exceeded expected time. |

On failure, the chat message stores the original `GenerationRequest` as
`retryRequest` so the retry button can rerun the same prompt/image/model.

## Credit Failure Behavior

Paid-credit generation can block or fail for Nova3D credits in three places:

1. Home page preflight before conversation creation.
2. Chat provider preflight before `/run/state/sketch_to_3d_v2`.
3. GraphFlow start/status/result responses.

If `/credits/estimate` or `/run/state` returns 402, the frontend tries to parse
required and available credits from the backend detail text. If parsed, the
message is:

```text
This model needs {required} credits, but you have {available} available. Buy more credits at /subscription and try again.
```

Otherwise it shows:

```text
You do not have enough Nova3D credits for this model. Buy more credits at /subscription and try again.
```

If `runtime.state == budget_exhausted`, the frontend throws:

```text
Your provider or generation budget was exhausted before the model completed.
```

BYOK initial generation skips Nova3D credit checks. Provider-side key, quota,
balance, and rate-limit failures are expected to surface through GraphFlow/tool
failure payloads, especially `error_category` values such as
`invalid_api_key`, `insufficient_credits`, and `quota_or_rate_limit`.


## Current BYOK Boundary

Current client BYOK initial generation is v2:

```text
workflow: sketch_to_3d_byok_v2
payload: prompt, code_llm_profile, code_llm_tier, code_llm_provider, code_llm_api_key, optional image_artifact list
return_nodes: final_validated_correction, final_latest_valid, fail_generation, require_byok_api_key
```

Current paid v2 is:

```text
workflow: sketch_to_3d_v2
payload: prompt, code_llm_profile, code_llm_tier, optional image_artifact list
return_nodes: final_validated_correction, final_latest_valid, fail_generation
```

## Acceptance Test Matrix

Use these cases when checking the current v2 integration or a future refactor:

| Case | Expected frontend behavior |
|---|---|
| Paid text-only generation | Calls readiness, estimate, wallet, start, status, result; final chat has GLB. |
| Paid image generation | Sends `has_reference_images` and `image_artifact` list; caption progress can appear. |
| Insufficient Nova3D credits before start | Blocks before start and shows credit message with `/subscription` action. |
| BYOK text-only generation | Calls readiness, start, status, result; skips Nova3D credit estimate and wallet checks. |
| BYOK image generation | Sends `has_reference_images` and `image_artifact` list with `code_llm_api_key`. |
| BYOK missing local key | Does not start generation; asks the user for a provider key. |
| BYOK rejected/empty provider key from workflow | Shows the best GraphFlow/tool failure message, including key-specific category fallbacks. |
| Start receive timeout | Keeps polling with the requested workflow id. |
| GraphFlow reaches `final_latest_valid` | Parses GLB/code artifacts and finalizes success. |
| GraphFlow reaches `final_validated_correction` | Parses corrected GLB/code artifacts and finalizes success. |
| GraphFlow reaches `fail_generation` | Shows the best available user message and enables retry. |
| GraphFlow reaches `require_byok_api_key` | Shows provider-key failure and enables retry after key correction. |
| Status temporarily returns 404/502/503/504 | Continues polling unless auth or budget failure is present. |
| Auth token missing/expired | Stops and asks user to sign in again. |
| Self-hosted URL override | All generation calls use `CAD_BASE_URL`; wallet uses `API_BASE_URL`; auth uses `AUTH_BASE_URL`. |
| More than 3 images selected | Client attaches only up to 3 images and informs the user. |
| Oversized image dimensions | Client resizes to max 512px on the longest side without skewing. |
| Prompt longer than 40 words | Client blocks or rejects the edit before start. |

## Do Not Change Accidentally

These are intentional properties of the current working integration:

- Paid v2 does not send user provider API keys.
- Paid v2 does not send `llm` or `provider`.
- Paid v2 uses `code_llm_profile` and `code_llm_tier` as pricing/routing
  context.
- BYOK v2 sends only the selected user's provider key through
  `code_llm_api_key`; paid v2 never sends it.
- BYOK v2 does not perform Nova3D credit estimate/balance checks.
- BYOK v2 does not send legacy `api_key`, `provider`, `llm`, or `validate`.
- The frontend requests v2 terminal nodes in `return_nodes`.
- Polling is gentle at 3 seconds.
- The client treats start receive timeout as possibly-started.
- Failure messages should come from GraphFlow/tool payloads when available,
  instead of replacing them with a generic error.
