import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'device.dart';
import 'exception.dart';
import 'options.dart';
import 'queue.dart';
import 'storage.dart';
import 'transport.dart';

const _maxBreadcrumbs = 20;
const _maxBackoff = Duration(minutes: 5);

/// Sends a Flutter app's logs and errors to a Tailcove source.
///
/// Lines wait in a queue and go out in batches (up to [TailcoveOptions.batchSize], or
/// [TailcoveOptions.flushInterval] after the first, or when the app goes to the background), with the app key and app
/// id in headers. A batch that fails for a reason that may pass (offline, 429, 5xx) stays queued and is retried with
/// backoff, and the queue is kept in a file so it survives restarts. Every line carries the app id and version, the
/// OS and a session id. Nothing here throws into the app.
class Tailcove {
  /// Creates a client. Most apps call [Tailcove.init] or [Tailcove.runApp] instead.
  Tailcove(TailcoveOptions options)
      : _options = options,
        _enabled = options.enabled && options.appKey.isNotEmpty,
        _endpoint = Uri.parse(options.endpoint),
        _http = options.httpClient ?? http.Client(),
        _ownsHttp = options.httpClient == null,
        _host = osName() {
    _baseContext = {
      ...deviceContext(),
      'app': {'id': options.appId, if (options.release != null) 'version': options.release},
      if (options.environment != null) 'environment': options.environment,
      'session_id': _sessionId(),
    };
    _context = {...options.context};
    _queue = PersistentQueue(
      max(1, options.maxQueueSize),
      _enabled && options.persistQueue ? (options.storage ?? TailcoveStorage.applicationSupport()) : null,
      _handleError,
    );

    if (_enabled) {
      // Lines kept from an earlier launch go out once they are back.
      _queue.ready.then((_) {
        if (_queue.length > 0) {
          _scheduleFlush();
        }
      });
    }
  }

  static Tailcove? _current;

  /// Creates the client, makes it [Tailcove.instance], and hooks Flutter's error handlers and app lifecycle.
  static Tailcove init(TailcoveOptions options) {
    _current?.close();
    final client = Tailcove(options);
    _current = client;
    client._attach();

    return client;
  }

  /// Sets up Flutter, starts the client, then runs your app: `Tailcove.runApp(options, () => runApp(const MyApp()))`.
  static Future<void> runApp(TailcoveOptions options, FutureOr<void> Function() appRunner) async {
    WidgetsFlutterBinding.ensureInitialized();
    init(options);
    await appRunner();
  }

  /// The client [init] made; a silent one before that, so a log call never fails.
  static Tailcove get instance => _current ??= Tailcove(const TailcoveOptions(appKey: '', appId: '', enabled: false));

  final TailcoveOptions _options;
  final bool _enabled;
  final Uri _endpoint;
  final http.Client _http;
  final bool _ownsHttp;
  final String _host;
  late final Map<String, Object?> _baseContext;
  late Map<String, Object?> _context;
  late final PersistentQueue _queue;

  final List<Map<String, Object?>> _breadcrumbs = [];
  final List<void Function()> _detach = [];
  Timer? _timer;
  Future<void>? _sending;
  Duration _backoff = Duration.zero;
  DateTime? _retryAt;
  bool _closed = false;

  void log(TailcoveLevel level, String message, [Map<String, Object?> context = const {}]) {
    if (!_enabled) {
      return;
    }

    try {
      final ts = clock.now().toUtc().toIso8601String();

      _queue.push({
        'message': message,
        'level': level.name,
        'context': {..._baseContext, ..._context, ...context},
        'host': _host,
        'ts': ts,
      });
      _remember(level, message, ts);

      if (_queue.length >= _options.batchSize) {
        flush();
      } else {
        _scheduleFlush();
      }
    } catch (error) {
      _handleError(error);
    }
  }

  void debug(String message, [Map<String, Object?> context = const {}]) => log(TailcoveLevel.debug, message, context);

  void info(String message, [Map<String, Object?> context = const {}]) => log(TailcoveLevel.info, message, context);

  void notice(String message, [Map<String, Object?> context = const {}]) => log(TailcoveLevel.notice, message, context);

  void warning(String message, [Map<String, Object?> context = const {}]) =>
      log(TailcoveLevel.warning, message, context);

  void error(String message, [Map<String, Object?> context = const {}]) => log(TailcoveLevel.error, message, context);

  void critical(String message, [Map<String, Object?> context = const {}]) =>
      log(TailcoveLevel.critical, message, context);

  void alert(String message, [Map<String, Object?> context = const {}]) => log(TailcoveLevel.alert, message, context);

  void emergency(String message, [Map<String, Object?> context = const {}]) =>
      log(TailcoveLevel.emergency, message, context);

  /// Reports an error with the exception shape every Tailcove client sends (so it groups into an issue) and the last
  /// log calls before it as breadcrumbs.
  void captureException(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
    TailcoveLevel level = TailcoveLevel.error,
  }) {
    if (!_enabled) {
      return;
    }

    try {
      final exception = formatException(error, stackTrace ?? StackTrace.current, traceLimit: _options.traceLimit);
      final message = exception['message'] as String;

      log(level, message.isEmpty ? exception['class'] as String : message, {
        ...context,
        'exception': exception,
        'breadcrumbs': List<Map<String, Object?>>.of(_breadcrumbs),
      });
    } catch (failure) {
      _handleError(failure);
    }
  }

  /// Adds a step to the trail sent with the next error, without sending a line of its own.
  void addBreadcrumb(String message, {TailcoveLevel level = TailcoveLevel.info}) =>
      _remember(level, message, clock.now().toUtc().toIso8601String());

  /// The signed-in user's id on every following line (only an id: no name or email is ever sent). Null clears it.
  void setUser(Object? id) {
    if (id == null) {
      _context.remove('user');
    } else {
      _context['user'] = {'id': id.toString()};
    }
  }

  /// Merges keys into the context of every following line; a key set to null is removed.
  void setContext(Map<String, Object?> values) {
    values.forEach((key, value) {
      if (value == null) {
        _context.remove(key);
      } else {
        _context[key] = value;
      }
    });
  }

  /// Sends what is waiting now, batch after batch, until the queue is empty or a send fails.
  Future<void> flush() {
    if (!_enabled) {
      return Future.value();
    }

    return _sending ??= _drain().whenComplete(() {
      _sending = null;

      // Lines left after a failed attempt, or written meanwhile, wait for the next timer (backoff included).
      if (_queue.length > 0 && !_closed) {
        _scheduleFlush();
      }
    });
  }

  /// Sends and saves what is waiting, and lets go of the error handlers and lifecycle observer.
  Future<void> close() async {
    _closed = true;

    for (final detach in _detach.reversed) {
      detach();
    }
    _detach.clear();

    if (identical(_current, this)) {
      _current = null;
    }

    await flush();
    _timer?.cancel();
    _timer = null;
    await _queue.save();
    _queue.dispose();

    if (_ownsHttp) {
      _http.close();
    }
  }

  Future<void> _drain() async {
    _timer?.cancel();
    _timer = null;

    await _queue.ready;

    final retryAt = _retryAt;
    if (retryAt != null && clock.now().isBefore(retryAt)) {
      return;
    }

    while (_queue.length > 0) {
      final batch = _queue.peek(_options.batchSize);
      final result = await sendBatch(
        client: _http,
        endpoint: _endpoint,
        appKey: _options.appKey,
        appId: _options.appId,
        timeout: _options.timeout,
        batch: batch,
      );

      switch (result) {
        case Retry(:final error, :final retryAfter):
          final doubled = _backoff == Duration.zero ? const Duration(seconds: 1) : _backoff * 2;
          _backoff = doubled > _maxBackoff ? _maxBackoff : doubled;
          _retryAt = clock.now().add(retryAfter ?? _backoff);
          _handleError(error);

          return;
        case Drop(:final error):
          _handleError(error);
        case Sent():
          break;
      }

      _queue.ack(batch);
      _backoff = Duration.zero;
      _retryAt = null;
    }
  }

  void _attach() {
    if (!_enabled) {
      return;
    }

    final binding = WidgetsFlutterBinding.ensureInitialized();
    final observer = _Lifecycle(() {
      flush().then((_) => _queue.save());
    });
    binding.addObserver(observer);
    _detach.add(() => binding.removeObserver(observer));

    if (!_options.captureErrors) {
      return;
    }

    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      _reportFlutterError(details);
      (previousFlutter ?? FlutterError.presentError)(details);
    };
    _detach.add(() => FlutterError.onError = previousFlutter);

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatform = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      captureException(error, stackTrace: stack, context: const {'handled': false});
      _queue.save();

      return previousPlatform?.call(error, stack) ?? false;
    };
    _detach.add(() => dispatcher.onError = previousPlatform);
  }

  /// Errors Flutter caught itself: build, layout and paint failures, gesture handlers.
  void _reportFlutterError(FlutterErrorDetails details) {
    final context = <String, Object?>{'handled': false, 'source': 'flutter'};

    if (details.library != null) {
      context['library'] = details.library;
    }

    final description = details.context?.toDescription();
    if (description != null && description.isNotEmpty) {
      context['while'] = description;
    }

    captureException(details.exception, stackTrace: details.stack, context: context);
    _queue.save();
  }

  void _remember(TailcoveLevel level, String message, String ts) {
    _breadcrumbs.add({
      'ts': ts,
      'level': level.name,
      'message': message.length > 200 ? message.substring(0, 200) : message,
    });

    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
  }

  void _scheduleFlush() {
    if (_timer != null || _sending != null || _closed) {
      return;
    }

    var delay = _options.flushInterval;
    final retryAt = _retryAt;

    if (retryAt != null) {
      final untilRetry = retryAt.difference(clock.now());
      if (untilRetry > delay) {
        delay = untilRetry;
      }
    }

    _timer = Timer(delay, () {
      _timer = null;
      flush();
    });
  }

  void _handleError(Object error) {
    try {
      _options.onError?.call(error);
    } catch (_) {
      // onError itself must never throw back into the app.
    }
  }

  /// For tests: whether lines are waiting.
  @visibleForTesting
  int get pendingLines => _queue.length;
}

/// Records route changes as breadcrumbs: add it to `MaterialApp(navigatorObservers: [TailcoveNavigatorObserver()])`.
class TailcoveNavigatorObserver extends NavigatorObserver {
  TailcoveNavigatorObserver([Tailcove? client]) : _client = client;

  final Tailcove? _client;

  Tailcove get _tailcove => _client ?? Tailcove.instance;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _tailcove.addBreadcrumb('Opened ${_name(route)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _tailcove.addBreadcrumb('Closed ${_name(route)}');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _tailcove.addBreadcrumb('Replaced with ${_name(newRoute)}');
    }
  }

  String _name(Route<dynamic> route) => route.settings.name ?? route.runtimeType.toString();
}

class _Lifecycle extends WidgetsBindingObserver {
  _Lifecycle(this._onBackground);

  final void Function() _onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _onBackground();
    }
  }
}

String _sessionId() {
  final random = Random.secure();

  return List.generate(8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
