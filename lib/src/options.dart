import 'package:http/http.dart' as http;

import 'storage.dart';

/// The levels the ingest endpoint understands. Anything else becomes `info`, as on the server.
enum TailcoveLevel { debug, info, notice, warning, error, critical, alert, emergency }

/// How the client is set up. Only [appKey] and [appId] are required.
class TailcoveOptions {
  const TailcoveOptions({
    required this.appKey,
    required this.appId,
    this.endpoint = 'https://ingest.tailcove.dev/api/v1/app/logs',
    this.release,
    this.environment,
    this.context = const {},
    this.batchSize = 50,
    this.flushInterval = const Duration(seconds: 5),
    this.maxQueueSize = 1000,
    this.timeout = const Duration(seconds: 10),
    this.storage,
    this.persistQueue = true,
    this.captureErrors = true,
    this.traceLimit = 20,
    this.enabled = true,
    this.onError,
    this.httpClient,
  });

  /// The source's app key (Settings > Mobile apps). It ships inside the app: public by design.
  final String appKey;

  /// The app's iOS bundle id or Android package name. It must be one of the app ids allowed for the key.
  final String appId;

  /// Where batches go. Change it only if you self-host.
  final String endpoint;

  /// The app version, added to every line as `app.version`.
  final String? release;

  /// `production`, `staging` and the like, added to every line.
  final String? environment;

  /// Merged into every line's context, under the per-call context.
  final Map<String, Object?> context;

  /// Send once this many lines are waiting.
  final int batchSize;

  /// Send this long after the first waiting line.
  final Duration flushInterval;

  /// Lines kept while offline; past it the oldest go first.
  final int maxQueueSize;

  /// How long one delivery attempt may take.
  final Duration timeout;

  /// Where unsent lines are kept between launches. Defaults to a file in the app's support directory.
  final TailcoveStorage? storage;

  /// Set false to keep unsent lines in memory only.
  final bool persistQueue;

  /// Report uncaught Flutter and Dart errors.
  final bool captureErrors;

  /// Stack frames kept per reported error.
  final int traceLimit;

  /// Set false to keep the client silent: nothing is queued or sent.
  final bool enabled;

  /// Called when a batch cannot be sent or is refused. Failures are otherwise silent.
  final void Function(Object error)? onError;

  /// For tests and custom networking.
  final http.Client? httpClient;
}
