// Integration tests send key events through Flutter's focus system. When the
// desktop doesn't give the test window OS focus (e.g. GNOME's focus-stealing
// prevention while you type elsewhere), Flutter parks focus on the root scope:
// keys go nowhere and widgets that autofocus meanwhile (a new route) never get
// focus. These helpers tell Flutter the view is focused, restoring the widget
// that last had focus.
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void focusView(WidgetTester tester) {
  // Real key presses that reached the test window (someone typing while tests
  // run) can leave modifiers "held", and then exact shortcuts like Space stop
  // matching. Start each simulated key from a clean keyboard state.
  HardwareKeyboard.instance.clearState();
  tester.binding.handleViewFocusChanged(ViewFocusEvent(
    viewId: tester.view.viewId,
    state: ViewFocusState.focused,
    direction: ViewFocusDirection.undefined, // restore the last focused widget, not the first one
  ));
}

/// Call in wait loops: re-focuses the view only while focus is parked on the root.
void keepViewFocused(WidgetTester tester) {
  if (identical(FocusManager.instance.primaryFocus, FocusManager.instance.rootScope)) focusView(tester);
}

/// Ignores the OS telling Flutter the window lost focus (window managers send
/// that on full-screen switches or when another window is active), so key events
/// in tests never depend on the desktop. Call once at the start of a test.
void ignoreOsFocusLoss(WidgetTester tester) {
  // Call the binding directly: the test dispatcher's getter returns a wrapper
  // that would call this filter again.
  final binding = tester.binding;
  binding.platformDispatcher.onViewFocusChange = (event) {
    if (event.state == ViewFocusState.focused) binding.handleViewFocusChanged(event);
  };
  focusView(tester);
}
