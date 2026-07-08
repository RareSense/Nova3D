/// Toggles pointer events on the embedded 3D viewer iframes.
///
/// On Flutter web an `HtmlElementView` (the viewer iframe) captures pointer
/// events across its screen region, so a Flutter dialog painted over it does
/// not receive taps. Disabling the iframes' pointer events for the lifetime of
/// a modal lets the dialog's controls work again; non-web compilation is a
/// no-op.
library;

export 'viewer_pointer_guard_stub.dart'
    if (dart.library.js_interop) 'viewer_pointer_guard_web.dart';
