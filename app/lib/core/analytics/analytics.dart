// Nova3D product analytics — the single entry point the rest of the app uses.
//
// DESIGN CONTRACT
//
// 1. NEVER BREAKS THE APP. Every public method swallows its own errors. An
//    analytics outage, a blocked script, or a malformed property must never
//    surface to a user or abort a generation. There is no `rethrow` in here.
//
// 2. OFF BY DEFAULT IN FORKS. `kPostHogKey` is a `--dart-define` that defaults
//    to empty. With no key, `init()` returns early and every call is a cheap
//    no-op. This repo is public and self-hostable: a fork must never emit
//    events into Nova3D's project, and no PostHog credential is committed.
//
// 3. NO SECRETS, EVER. `_scrub` drops property names that look like
//    credentials AND redacts values that look like provider keys (sk-…,
//    sk-ant-…, AIza…, n3d_…, phc_…). Prompts are user-authored free text that
//    we do capture, so a key pasted into a prompt is a real risk — value-level
//    redaction is the backstop for that, not an afterthought.
//
// 4. REPLAY PAUSES AROUND SECRETS. The app renders to a canvas, so session
//    replay captures pixels; input masking cannot protect a provider key drawn
//    into the Flutter canvas on the API-keys screen. `pauseReplay` /
//    `resumeReplay` bracket those routes instead. See AnalyticsRouteObserver.

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:nova3d_frontend/core/analytics/analytics_events.dart';
import 'package:nova3d_frontend/core/analytics/analytics_scrubber.dart';
import 'package:nova3d_frontend/core/analytics/posthog_interop.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:web/web.dart' as web;

class Analytics {
  Analytics._();

  static final Analytics instance = Analytics._();

  bool _initialized = false;
  int _replayPauseDepth = 0;
  String? _identifiedUserId;

  /// True once posthog-js is present AND a key was supplied at build time.
  bool get isEnabled => _initialized && posthogJs != null;

  // ── Boot ───────────────────────────────────────────────────────────────────

  /// Initializes posthog-js. Safe to call more than once; later calls no-op.
  ///
  /// Called from `main()` before `runApp` so session replay starts as early as
  /// possible. It cannot cover the pre-Flutter HTML splash — that's why
  /// [Ev.appBooted] carries `boot_ms` from the browser's navigation timing.
  void init() {
    if (_initialized) return;
    if (!kIsWeb) return;
    if (kPostHogKey.isEmpty) {
      // Expected for forks / self-hosters. Debug-only note; never a warning.
      if (kDebugMode) {
        debugPrint(
          '[Analytics] No POSTHOG_KEY dart-define — analytics disabled.',
        );
      }
      return;
    }

    final ph = posthogJs;
    if (ph == null) {
      if (kDebugMode) {
        debugPrint('[Analytics] posthog-js not on window — analytics disabled.');
      }
      return;
    }

    try {
      ph.init(kPostHogKey, _initConfig());
      _initialized = true;
      _registerSuperProperties();
      _captureBoot();
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] init failed: $e');
    }
  }

  JSObject _initConfig() {
    return <String, Object?>{
      'api_host': kPostHogHost,
      'ui_host': kPostHogUiHost,

      // Pins SDK behavioural defaults so an upgrade cannot silently change what
      // gets captured. Everything set explicitly below still overrides it.
      'defaults': kPostHogDefaults,

      // Person profiles only for signed-in users. Anonymous showcase traffic
      // still produces events (and funnels) without billing a person profile.
      'person_profiles': 'identified_only',

      // GoRouter owns navigation, so pageviews are captured manually with the
      // matched route pattern. Auto-capture would double-count and would only
      // ever see raw paths.
      'capture_pageview': false,
      'capture_pageleave': true,

      // DOM autocapture is near-useless for the CanvasKit-rendered Flutter
      // shell, but the editor iframe is real DOM — this is what gives the
      // Three.js toolbar free click/heatmap coverage.
      'autocapture': true,
      'rageclick': true,
      'capture_performance': true,

      'session_recording': <String, Object?>{
        'maskAllInputs': true,
        'maskInputOptions': <String, Object?>{
          'password': true,
          'email': false,
          'text': false,
        },
        // Opt-in masking hooks for any DOM we add later that shows secrets.
        'maskTextSelector': '[data-ph-mask]',
        'blockSelector': '[data-ph-block]',

        // Flutter web paints into a <canvas>; without this every replay is a
        // blank page. Values chosen for readable 3D-viewport playback.
        //
        // `recordCanvas` is the switch, not just a tuning value — posthog-js
        // documents `captureCanvas` as "allows local config to override remote
        // canvas recording settings from the flags response", so setting it
        // here enables canvas capture even while the PROJECT-level toggle
        // (session_replay_config.record_canvas, admin-only) is still off.
        // Without it, canvasFps/canvasQuality tune a feature that never starts.
        'captureCanvas': <String, Object?>{
          'recordCanvas': true,
          'canvasFps': kReplayCanvasFps,
          'canvasQuality': kReplayCanvasQuality,
        },

        // Separate from `captureCanvas` despite the near-identical name.
        // `resolutionScale` captures frames at a fraction of display
        // resolution; replay upscales them back, so playback dimensions are
        // unchanged and only sharpness drops. Bytes scale with pixel area,
        // which makes this the highest-leverage lever if replay volume gets
        // expensive on a 3D app — turn this down before dropping fps.
        'canvasCapture': <String, Object?>{
          'resolutionScale':
              double.tryParse(kReplayCanvasResolutionScale) ?? 1.0,
        },
      },

      'persistence': 'localStorage+cookie',
      'disable_session_recording': false,
      'enable_heatmaps': true,
    }.jsify() as JSObject;
  }

  void _registerSuperProperties() {
    final view = web.window;
    _guard(() {
      posthogJs?.register(
        _scrub(<String, Object?>{
          Pr.appVersion: kAppVersion,
          Pr.buildMode: kReleaseMode ? 'release' : 'debug',
          Pr.renderer: 'canvaskit',
          Pr.devicePixelRatio: view.devicePixelRatio,
        }),
      );
    });
  }

  void _captureBoot() {
    num? bootMs;
    try {
      // `performance.now()` at first Dart execution is a good proxy for
      // "time from navigation start until the app was interactive".
      bootMs = web.window.performance.now();
    } catch (_) {
      bootMs = null;
    }
    capture(Ev.appBooted, <String, Object?>{
      Pr.bootMs: bootMs?.round(),
      Pr.viewportW: web.window.innerWidth,
      Pr.viewportH: web.window.innerHeight,
    });
  }

  // ── Identity ───────────────────────────────────────────────────────────────

  /// Links the current anonymous session to a user. Idempotent per user id, so
  /// it is safe to call from an auth listener that fires on every rebuild.
  void identify({
    required String userId,
    String? email,
    bool? isVerified,
    Map<String, Object?> extraPersonProperties = const {},
  }) {
    if (_identifiedUserId == userId) return;
    _identifiedUserId = userId;
    _guard(() {
      posthogJs?.identify(
        userId,
        _scrub(<String, Object?>{
          if (kCaptureUserContent && email != null) Pr.email: email,
          Pr.isVerified: ?isVerified,
          ...extraPersonProperties,
        }),
      );
    });
  }

  /// Merges properties onto the current person (e.g. wallet balance changes).
  void setPersonProperties(Map<String, Object?> properties) {
    _guard(() => posthogJs?.setPersonProperties(_scrub(properties)));
  }

  /// Clears identity + starts a fresh anonymous session. Call on sign-out so a
  /// shared browser does not attribute the next user's events to the last one.
  void reset() {
    _identifiedUserId = null;
    _guard(() => posthogJs?.reset());
  }

  // ── Capture ────────────────────────────────────────────────────────────────

  void capture(String event, [Map<String, Object?> properties = const {}]) {
    if (!isEnabled) return;
    _guard(() => posthogJs?.capture(event, _scrub(properties)));
  }

  /// Manual pageview carrying the GoRouter pattern (`/chat/:id`) alongside the
  /// concrete path, so insights can group by screen without high-cardinality
  /// path explosion.
  void pageview({
    required String path,
    String? pattern,
    String? previousPath,
  }) {
    capture(Ev.pageview, <String, Object?>{
      Pr.route: path,
      Pr.routePattern: ?pattern,
      Pr.previousRoute: ?previousPath,
    });
  }

  /// Reports a Dart error to PostHog error tracking as a real JS `Error`, so it
  /// groups into an issue instead of an untyped blob.
  void captureException(
    Object error,
    StackTrace? stack, {
    String? context,
    bool handled = true,
    Map<String, Object?> properties = const {},
  }) {
    if (!isEnabled) return;
    _guard(() {
      final message = truncate(redactSecrets(error.toString()));
      final jsError = JsError(message)
        ..name = error.runtimeType.toString()
        // Stacks get the longer cap: a truncated stack is a useless stack.
        ..stack = truncate(
          '${error.runtimeType}: $message\n${stack ?? StackTrace.current}',
          maxLength: kMaxStackLength,
        );
      posthogJs?.captureException(
        jsError,
        _scrub(<String, Object?>{
          Pr.context: ?context,
          Pr.handled: handled,
          ...properties,
        }),
      );
    });
  }

  /// A handled error that the user actually saw. Complements `$exception`,
  /// which only covers crashes.
  void errorShown({
    required String message,
    String? context,
    String? category,
    Map<String, Object?> properties = const {},
  }) {
    capture(Ev.errorShown, <String, Object?>{
      Pr.errorMessage: message,
      Pr.context: ?context,
      Pr.errorCategory: ?category,
      ...properties,
    });
  }

  // ── Session replay control ────────────────────────────────────────────────

  /// Stops recording while a secret is on screen. Reference-counted, because
  /// nested guards (a dialog over the API-keys page) must not resume early.
  void pauseReplay() {
    _replayPauseDepth++;
    if (_replayPauseDepth == 1) {
      _guard(() => posthogJs?.stopSessionRecording());
    }
  }

  void resumeReplay() {
    if (_replayPauseDepth == 0) return;
    _replayPauseDepth--;
    if (_replayPauseDepth == 0) {
      _guard(() => posthogJs?.startSessionRecording());
    }
  }

  /// Deep link to the replay of the session that produced an event — handy to
  /// attach to a failed generation so a support reply can jump straight to it.
  String? get sessionReplayUrl {
    if (!isEnabled) return null;
    try {
      return posthogJs?.getSessionReplayUrl();
    } catch (_) {
      return null;
    }
  }

  String? get sessionId {
    if (!isEnabled) return null;
    try {
      return posthogJs?.getSessionId();
    } catch (_) {
      return null;
    }
  }

  // ── Feature flags ─────────────────────────────────────────────────────────

  bool isFeatureEnabled(String flag, {bool defaultValue = false}) {
    if (!isEnabled) return defaultValue;
    try {
      return posthogJs?.isFeatureEnabled(flag) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  // ── Opt out ───────────────────────────────────────────────────────────────

  void optOut() => _guard(() => posthogJs?.optOutCapturing());
  void optIn() => _guard(() => posthogJs?.optInCapturing());
  bool get hasOptedOut {
    if (!isEnabled) return false;
    try {
      return posthogJs?.hasOptedOutCapturing() ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _guard(void Function() body) {
    if (!kIsWeb) return;
    try {
      body();
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] call failed: $e');
    }
  }

  /// Scrubs properties (see analytics_scrubber.dart — the privacy boundary,
  /// unit-tested on the VM) and converts the result to a JS object.
  JSObject _scrub(Map<String, Object?> properties) =>
      scrubProperties(properties).jsify() as JSObject;

}

/// Convenience accessor so call sites read as `analytics.capture(...)`.
Analytics get analytics => Analytics.instance;
