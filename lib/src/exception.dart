/// The exception shape every Tailcove client sends (`class`, `message`, `location`, `trace`), so a Dart error groups
/// into an issue the way a server one does.
Map<String, Object?> formatException(Object error, StackTrace? stackTrace, {int traceLimit = 20}) {
  final frames = _frames(stackTrace);

  return {
    'class': error.runtimeType.toString(),
    'message': _message(error),
    'location': frames.isEmpty ? 'unknown:0' : _location(frames.first),
    'trace': frames.take(traceLimit).toList(),
  };
}

String _message(Object error) {
  final text = error.toString();

  // "Exception: payment failed" reads better as "payment failed"; the class is already its own field.
  for (final prefix in const ['Exception: ', 'Bad state: ', 'Invalid argument(s): ']) {
    if (text.startsWith(prefix) && text.length > prefix.length) {
      return text.substring(prefix.length);
    }
  }

  return text;
}

List<String> _frames(StackTrace? stackTrace) {
  if (stackTrace == null) {
    return const [];
  }

  return stackTrace
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line != '<asynchronous suspension>')
      .toList();
}

// "#0      CartPage.pay (package:shop/cart_page.dart:42:7)"
final _vmFrame = RegExp(r'\((.+?):(\d+)(?::\d+)?\)$');

String _location(String frame) {
  final match = _vmFrame.firstMatch(frame);

  return match == null ? 'unknown:0' : '${match.group(1)}:${match.group(2)}';
}
