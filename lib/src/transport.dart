import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What became of one delivery attempt.
sealed class SendResult {
  const SendResult();
}

class Sent extends SendResult {
  const Sent();
}

/// Worth trying again later (offline, timeout, 429, 5xx).
class Retry extends SendResult {
  const Retry(this.error, [this.retryAfter]);

  final Object error;
  final Duration? retryAfter;
}

/// Refused for good (a bad key, an app id not allowed, a malformed batch): sending it again changes nothing.
class Drop extends SendResult {
  const Drop(this.error);

  final Object error;
}

class TailcoveHttpException implements Exception {
  TailcoveHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'tailcove: ingest endpoint responded with status $statusCode';
}

/// POSTs one batch as a JSON array with the app key and app id in headers. Never throws.
Future<SendResult> sendBatch({
  required http.Client client,
  required Uri endpoint,
  required String appKey,
  required String appId,
  required Duration timeout,
  required List<Map<String, Object?>> batch,
}) async {
  try {
    final response = await client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'X-Tailcove-App-Key': appKey,
            'X-Tailcove-App-Id': appId,
          },
          body: jsonEncode(batch),
        )
        .timeout(timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const Sent();
    }

    final error = TailcoveHttpException(response.statusCode);

    if (response.statusCode == 429 || response.statusCode == 408 || response.statusCode >= 500) {
      return Retry(error, _retryAfter(response.headers['retry-after']));
    }

    return Drop(error);
  } catch (error) {
    return Retry(error);
  }
}

Duration? _retryAfter(String? header) {
  final seconds = header == null ? null : int.tryParse(header.trim());

  return seconds == null || seconds < 0 ? null : Duration(seconds: seconds > 3600 ? 3600 : seconds);
}
