import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailcove_flutter/tailcove_flutter.dart';

/// A fake ingest endpoint answering with the given statuses in turn (the last repeats), recording each request.
class FakeIngest {
  FakeIngest(List<Object> answers) : _answers = answers.isEmpty ? [202] : answers;

  final List<Object> _answers;
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final answer = _answers[(requests.length - 1).clamp(0, _answers.length - 1)];

    if (answer is Exception) {
      throw answer;
    }

    if (answer is http.Response) {
      return answer;
    }

    return http.Response('', answer as int);
  });

  List<Map<String, dynamic>> lines(int index) =>
      (jsonDecode(requests[index].body) as List).cast<Map<String, dynamic>>();
}

Tailcove makeClient(
  FakeIngest ingest, {
  TailcoveStorage? storage,
  int batchSize = 50,
  Duration flushInterval = const Duration(seconds: 5),
  int maxQueueSize = 1000,
  void Function(Object)? onError,
  String? release,
}) =>
    Tailcove(TailcoveOptions(
      appKey: 'tca_${'a' * 32}',
      appId: 'com.acme.shop',
      endpoint: 'https://ingest.example.test/api/v1/app/logs',
      httpClient: ingest.client,
      storage: storage ?? MemoryTailcoveStorage(),
      batchSize: batchSize,
      flushInterval: flushInterval,
      maxQueueSize: maxQueueSize,
      onError: onError,
      release: release,
      environment: 'production',
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sending', () {
    test('batches lines with the app key and app id in headers', () async {
      final ingest = FakeIngest([202]);
      final tailcove = makeClient(ingest, release: '2.4.0');

      tailcove.info('App started', {'screen': 'Home'});
      tailcove.error('Payment failed');
      await tailcove.flush();

      expect(ingest.requests, hasLength(1));
      final request = ingest.requests.single;
      expect(request.url.toString(), 'https://ingest.example.test/api/v1/app/logs');
      expect(request.headers['X-Tailcove-App-Key'], 'tca_${'a' * 32}');
      expect(request.headers['X-Tailcove-App-Id'], 'com.acme.shop');

      final lines = ingest.lines(0);
      expect(lines[0]['message'], 'App started');
      expect(lines[0]['level'], 'info');
      expect(lines[0]['context']['screen'], 'Home');
      expect(lines[0]['context']['app'], {'id': 'com.acme.shop', 'version': '2.4.0'});
      expect(lines[0]['context']['environment'], 'production');
      expect(lines[0]['context']['os']['name'], isA<String>());
      expect(lines[0]['context']['session_id'], hasLength(16));
      expect(lines[1]['level'], 'error');
    });

    test('sends after the flush interval, and at once when a batch is full', () {
      fakeAsync((async) {
        final ingest = FakeIngest([202]);
        final tailcove = makeClient(ingest, batchSize: 3);

        tailcove.info('one');
        async.elapse(const Duration(milliseconds: 4999));
        expect(ingest.requests, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(ingest.requests, hasLength(1));

        tailcove
          ..info('a')
          ..info('b')
          ..info('c');
        async.flushMicrotasks();
        expect(ingest.requests, hasLength(2));
        expect(ingest.lines(1), hasLength(3));
      });
    });

    test('stays silent when disabled, without a key, and before init', () async {
      final ingest = FakeIngest([202]);

      Tailcove(TailcoveOptions(appKey: 'tca_x', appId: 'a.b', enabled: false, httpClient: ingest.client)).error('no');
      Tailcove(TailcoveOptions(appKey: '', appId: 'a.b', httpClient: ingest.client)).error('no');
      Tailcove.instance.error('before init');
      await Future<void>.delayed(Duration.zero);

      expect(ingest.requests, isEmpty);
    });
  });

  group('failures', () {
    test('keeps a batch that could not be sent and retries it with backoff', () {
      fakeAsync((async) {
        final errors = <Object>[];
        final ingest = FakeIngest([http.ClientException('offline'), 503, 202]);
        final tailcove = makeClient(ingest, flushInterval: const Duration(milliseconds: 100), onError: errors.add);

        tailcove.info('offline line');
        tailcove.flush();
        async.flushMicrotasks();
        expect(ingest.requests, hasLength(1));

        async.elapse(const Duration(seconds: 1));
        expect(ingest.requests, hasLength(2));

        async.elapse(const Duration(seconds: 2));
        expect(ingest.requests, hasLength(3));
        expect(ingest.lines(2).single['message'], 'offline line');
        expect(errors, hasLength(2));
        expect(tailcove.pendingLines, 0);
      });
    });

    test('waits as long as Retry-After says on a 429', () {
      fakeAsync((async) {
        final ingest = FakeIngest([
          http.Response('', 429, headers: {'retry-after': '30'}),
          202
        ]);
        final tailcove = makeClient(ingest, flushInterval: const Duration(milliseconds: 100));

        tailcove.info('rate limited');
        tailcove.flush();
        async.elapse(const Duration(seconds: 29));
        expect(ingest.requests, hasLength(1));
        async.elapse(const Duration(milliseconds: 1100));
        expect(ingest.requests, hasLength(2));
      });
    });

    test('drops a batch refused for good, and moves on', () async {
      final errors = <Object>[];
      final ingest = FakeIngest([403, 202]);
      final tailcove = makeClient(ingest, batchSize: 1, onError: errors.add);

      tailcove.info('refused');
      await tailcove.flush();
      tailcove.info('accepted');
      await tailcove.flush();

      expect(ingest.requests.map((r) => (jsonDecode(r.body) as List).single['message']), ['refused', 'accepted']);
      expect(errors.single.toString(), contains('403'));
    });

    test('never throws, even when onError does', () async {
      final ingest = FakeIngest([http.ClientException('boom')]);
      final tailcove = makeClient(ingest, onError: (_) => throw StateError('onError broke'));

      expect(() => tailcove.info('x'), returnsNormally);
      await expectLater(tailcove.flush(), completes);
    });

    test('drops the oldest lines past maxQueueSize', () async {
      final ingest = FakeIngest([202]);
      final tailcove = makeClient(ingest, maxQueueSize: 2);

      tailcove
        ..info('1')
        ..info('2')
        ..info('3');
      await tailcove.flush();

      expect(ingest.lines(0).map((line) => line['message']), ['2', '3']);
    });
  });

  group('the persistent queue', () {
    test('keeps unsent lines and sends them on the next launch', () async {
      final storage = MemoryTailcoveStorage();
      final offline = FakeIngest([http.ClientException('offline')]);
      final first = makeClient(offline, storage: storage);

      first.error('written offline');
      await first.flush();
      await first.close();
      expect((jsonDecode(storage.value!) as List).single['message'], 'written offline');

      final online = FakeIngest([202]);
      final second = makeClient(online, storage: storage);
      await Future<void>.delayed(Duration.zero);
      await second.flush();

      expect(online.lines(0).single['message'], 'written offline');
      await second.close();
      expect(storage.value, isNull);
    });

    test('ignores a stored queue it cannot read', () async {
      final ingest = FakeIngest([202]);
      final tailcove = makeClient(ingest, storage: MemoryTailcoveStorage('{not json'));

      tailcove.info('fresh');
      await tailcove.flush();

      expect(ingest.lines(0).map((line) => line['message']), ['fresh']);
    });
  });

  group('errors', () {
    test('captureException sends the exception shape and the breadcrumbs', () async {
      final ingest = FakeIngest([202]);
      final tailcove = makeClient(ingest);

      tailcove.info('opened cart');
      tailcove.addBreadcrumb('tapped pay');
      try {
        throw StateError('cart is empty');
      } catch (error, stack) {
        tailcove.captureException(error, stackTrace: stack, context: {'order': 7});
      }
      await tailcove.flush();

      final line = ingest.lines(0).last;
      expect(line['level'], 'error');
      expect(line['message'], 'cart is empty');
      expect(line['context']['order'], 7);
      expect(line['context']['exception']['class'], 'StateError');
      expect(line['context']['exception']['location'], contains('tailcove_test.dart'));
      expect((line['context']['breadcrumbs'] as List).map((crumb) => crumb['message']), ['opened cart', 'tapped pay']);
    });

    test('init hooks FlutterError.onError and PlatformDispatcher.onError, and close puts them back', () async {
      final ingest = FakeIngest([202]);
      final presented = <FlutterErrorDetails>[];
      final previousFlutter = FlutterError.onError;
      FlutterError.onError = presented.add;
      final dispatcher = PlatformDispatcher.instance;
      final previousPlatform = dispatcher.onError;
      final platformSeen = <Object>[];
      dispatcher.onError = (error, stack) {
        platformSeen.add(error);
        return true;
      };
      final ownHandler = FlutterError.onError;

      final tailcove = Tailcove.init(TailcoveOptions(
        appKey: 'tca_${'b' * 32}',
        appId: 'com.acme.shop',
        httpClient: ingest.client,
        storage: MemoryTailcoveStorage(),
      ));
      expect(Tailcove.instance, same(tailcove));

      FlutterError.onError!(FlutterErrorDetails(
        exception: FlutterError('A RenderFlex overflowed by 42 pixels'),
        library: 'rendering library',
        context: ErrorDescription('during layout'),
      ));
      final handled = dispatcher.onError!(Exception('socket closed'), StackTrace.current);
      await tailcove.flush();

      expect(presented, hasLength(1));
      expect(platformSeen, hasLength(1));
      expect(handled, isTrue);
      final lines = ingest.lines(0);
      expect(lines[0]['message'], 'A RenderFlex overflowed by 42 pixels');
      expect(lines[0]['context'], containsPair('library', 'rendering library'));
      expect(lines[0]['context'], containsPair('while', 'during layout'));
      expect(lines[1]['message'], 'socket closed');
      expect(lines[1]['context']['exception']['class'], '_Exception');

      await tailcove.close();
      expect(FlutterError.onError, same(ownHandler));
      dispatcher.onError = previousPlatform;
      FlutterError.onError = previousFlutter;
    });

    test('formatException reads VM frames', () {
      final stack = StackTrace.fromString(
          '#0      CartPage.pay (package:shop/cart_page.dart:42:7)\n<asynchronous suspension>\n#1      main (package:shop/main.dart:9:3)');
      final formatted = formatException(Exception('boom'), stack);

      expect(formatted['class'], '_Exception');
      expect(formatted['message'], 'boom');
      expect(formatted['location'], 'package:shop/cart_page.dart:42');
      expect(formatted['trace'], hasLength(2));
    });
  });

  group('context', () {
    test('adds only the user id and custom context to following lines', () async {
      final ingest = FakeIngest([202]);
      final tailcove = makeClient(ingest);

      tailcove.setUser(42);
      tailcove.setContext({'build': 'beta'});
      tailcove.info('signed in');
      tailcove.setUser(null);
      tailcove.setContext({'build': null});
      tailcove.info('signed out');
      await tailcove.flush();

      final lines = ingest.lines(0);
      expect(lines[0]['context']['user'], {'id': '42'});
      expect(lines[0]['context']['build'], 'beta');
      expect(lines[1]['context'], isNot(contains('user')));
      expect(lines[1]['context'], isNot(contains('build')));
    });

    test('the navigator observer leaves route breadcrumbs', () async {
      final ingest = FakeIngest([202]);
      final tailcove = makeClient(ingest);
      final observer = TailcoveNavigatorObserver(tailcove);

      observer.didPush(
          PageRouteBuilder<void>(
              settings: const RouteSettings(name: '/cart'), pageBuilder: (_, __, ___) => const SizedBox()),
          null);
      tailcove.captureException(Exception('x'));
      await tailcove.flush();

      expect((ingest.lines(0).single['context']['breadcrumbs'] as List).single['message'], 'Opened /cart');
    });
  });
}
