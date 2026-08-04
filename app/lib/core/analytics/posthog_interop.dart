// Raw `dart:js_interop` bindings for posthog-js.
//
// This file is the ONLY place that touches the JS SDK surface. Everything else
// in the app goes through `Analytics` (analytics.dart), which adds the null
// guard, property scrubbing, and try/catch isolation. Keeping the raw bindings
// separate means a posthog-js API change is a one-file edit.
//
// posthog-js is loaded by the stub snippet in `web/index.html`. That snippet
// defines `window.posthog` with queueing stubs BEFORE the real library arrives,
// so calls made during Flutter boot are buffered rather than lost. The token is
// NOT in the snippet — `Analytics.init()` calls `posthog.init()` from Dart with
// a build-time key, so forks of this open-source repo never ship events to the
// Nova3D project (see kPostHogKey in core/constants.dart).

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The subset of the posthog-js API this app uses.
///
/// Method names must match posthog-js exactly — they are JS property lookups,
/// not Dart identifiers, so a rename here silently becomes a no-op call.
extension type PostHogJs._(JSObject _) implements JSObject {
  external void init(String token, JSObject config);

  external void capture(String event, [JSObject? properties]);

  external void identify(String distinctId, [JSObject? personProperties]);

  /// Clears the stored person + resets the anonymous id. Call on sign-out so
  /// the next user on a shared browser does not inherit the previous identity.
  external void reset();

  /// Super properties — merged into every subsequent event, persisted.
  external void register(JSObject properties);

  external void unregister(String property);

  external void setPersonProperties(JSObject properties);

  external void group(String groupType, String groupKey, [JSObject? properties]);

  external void startSessionRecording();

  external void stopSessionRecording();

  /// posthog-js returns the replay URL for the *current* session, or null when
  /// recording has not started. Useful to stitch a failed run to its replay.
  @JS('get_session_replay_url')
  external String? getSessionReplayUrl();

  @JS('get_session_id')
  external String? getSessionId();

  @JS('get_distinct_id')
  external String? getDistinctId();

  external void captureException(JSAny error, [JSObject? properties]);

  external JSAny? getFeatureFlag(String key);

  external bool isFeatureEnabled(String key);

  @JS('opt_out_capturing')
  external void optOutCapturing();

  @JS('opt_in_capturing')
  external void optInCapturing();

  @JS('has_opted_out_capturing')
  external bool hasOptedOutCapturing();
}

/// `window.posthog`, or null when the snippet never loaded (e.g. a fork built
/// without a PostHog key, or an ad-blocker removed the script).
PostHogJs? get posthogJs {
  final global = globalContext;
  if (!global.has('posthog')) return null;
  final value = global.getProperty<JSAny?>('posthog'.toJS);
  if (value == null || !value.isA<JSObject>()) return null;
  return PostHogJs._(value as JSObject);
}

/// A real JS `Error`, so PostHog's error tracking can group and symbolicate it.
///
/// Dart exceptions are not JS Errors; passing a plain string to
/// `captureException` produces an ungrouped "Unknown" issue. Constructing an
/// Error and overwriting `name`/`stack` gives PostHog the shape it expects.
extension type JsError._(JSObject _) implements JSObject {
  external factory JsError(String message);

  external set name(String value);
  external set stack(String value);
}
