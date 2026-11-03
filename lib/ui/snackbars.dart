import 'package:flutter/material.dart';

/// Shows [message], replacing any snackbar that is already shown, so quick
/// repeated actions never queue up. With [onUndo], it has an Undo action.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showMessage(
  ScaffoldMessengerState? messenger,
  String message, {
  VoidCallback? onUndo,
}) {
  if (messenger == null) return null;
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: onUndo == null
          ? null
          : SnackBarAction(label: 'Undo', onPressed: onUndo),
      // Long enough to reach Undo; plain messages go away sooner. A snackbar
      // with an action would stay until dismissed by default.
      duration: Duration(seconds: onUndo == null ? 3 : 5),
      persist: false,
    ),
  );
}
