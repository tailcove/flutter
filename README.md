<a href="https://tailcove.dev/docs/sending-logs/flutter"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/flutter-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/flutter-light.svg"><img alt="tailcove_flutter: Tailcove for Flutter. Version, platforms and license." src="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/flutter-dark.svg" width="100%"></picture></a>

<p align="center">
  <a href="https://tailcove.dev/docs/sending-logs/flutter">Documentation</a> &nbsp;·&nbsp;
  <a href="https://tailcove.dev/register">Get started free</a> &nbsp;·&nbsp;
  <a href="https://pub.dev/packages/tailcove_flutter">View on pub.dev</a> &nbsp;·&nbsp;
  <a href="https://github.com/tailcove/flutter/issues/new/choose">Report a bug</a>
</p>

<h3 align="center">Send logs and Dart and Flutter errors from your Flutter app to Tailcove.</h3>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/features-flutter-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/features-flutter-light.svg">
  <img alt="tailcove_flutter features" src="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/features-flutter-dark.svg" width="100%">
</picture>

## Install

```bash
flutter pub add tailcove_flutter
```

Works on iOS, Android, macOS, Windows and Linux. On the web it sends, but cannot keep unsent lines across reloads.

## Quick start

**1. Get an app key.** In your [Tailcove dashboard](https://tailcove.dev), open your source's **Settings** tab, generate a key under **Mobile apps**, and add your app's iOS bundle id or Android package name (for example `com.acme.shop`, or `com.acme.*` for all of them).

> The app key ships inside your app, so it is **public by design**. It only works for the app ids you allowed, and it has its own rate limit, so a copied key cannot use up your source's quota. It is not the server-side ingest token, which must stay secret.

**2. Wrap `runApp`.** `Tailcove.runApp` sets up Flutter, starts the client and hooks Flutter's error handlers, then runs your app:

```dart
import 'package:flutter/material.dart';
import 'package:tailcove_flutter/tailcove_flutter.dart';

void main() {
  Tailcove.runApp(
    const TailcoveOptions(
      appKey: 'tca_your_app_key',
      appId: 'com.acme.shop',
      release: '2.4.0',
      environment: 'production',
    ),
    () => runApp(const MyApp()),
  );
}
```

**3. Log.**

```dart
Tailcove.instance.info('Checkout opened', {'items': 3});
Tailcove.instance.warning('Slow image load', {'ms': 2400});
Tailcove.instance.error('Payment failed', {'provider': 'stripe'});
```

## Errors

Flutter errors (build, layout and paint failures, through `FlutterError.onError`) and uncaught Dart errors (through `PlatformDispatcher.instance.onError`) are reported on their own as `error` lines, with the exception (class, message, location, stack) and the last 20 log calls before it. Tailcove groups them into issues. The handlers you had before keep running, so the red screen and console output in debug builds stay as they were.

Report an error you caught yourself:

```dart
try {
  await placeOrder();
} catch (error, stack) {
  Tailcove.instance.captureException(error, stackTrace: stack, context: {'orderId': orderId});
}
```

Route changes become breadcrumbs with the navigator observer:

```dart
MaterialApp(navigatorObservers: [TailcoveNavigatorObserver()], home: const HomePage());
```

Add a step without sending a line: `Tailcove.instance.addBreadcrumb('Tapped pay')`.

Native crashes in the iOS or Android host code are outside Dart. For those, add the Sentry Flutter SDK and point it at the DSN from your source's **Error tracking** section.

## Users and context

```dart
Tailcove.instance.setUser(user.id);            // only the id is sent, never a name or email
Tailcove.instance.setContext({'plan': 'pro'}); // on every following line
Tailcove.instance.setUser(null);               // on sign-out
```

## What gets added automatically

- `app.id` and `app.version`: your app id and `release`
- `os.name` and `os.version`
- `runtime`: the Dart version
- `environment`: when you set it
- `session_id`: a random id for this launch
- `host`: the OS name (`ios`, `android`, ...)

## Options

- `appKey` (required): the source's app key.
- `appId` (required): the app's bundle id or package name, as allowed in Settings.
- `endpoint`: defaults to `https://ingest.tailcove.dev/api/v1/app/logs`. Change it only if you self-host.
- `release`, `environment`, `context`: added to every line.
- `batchSize`: send once this many lines are waiting. Default `50`.
- `flushInterval`: send this long after the first waiting line. Default 5 seconds.
- `maxQueueSize`: lines kept while offline; past it the oldest go first. Default `1000`.
- `timeout`: how long one delivery attempt may take. Default 10 seconds.
- `storage`: where the queue is kept between launches. Defaults to a file in the app's support directory.
- `persistQueue`: set `false` to keep the queue in memory only.
- `captureErrors`: report Flutter and uncaught Dart errors. Default `true`.
- `traceLimit`: stack frames kept per error. Default `20`.
- `enabled`: set `false` to turn the client off, for example in tests.
- `onError`: called when a batch cannot be sent or is refused. Failures are otherwise silent.

## How delivery works

Lines wait in a queue and go out in batches, when `batchSize` is reached, `flushInterval` after the first one, or when the app goes to the background. A line leaves the queue only once Tailcove has accepted it. If the device is offline or the server asks it to slow down, the batch stays queued and is tried again with backoff (honouring `Retry-After`), and the queue file means lines written just before the app was killed go out on the next launch. A batch refused for good, for example after the key was revoked, is dropped and reported to `onError`. Nothing the client does throws into your app.

`await Tailcove.instance.flush()` sends now, and `await Tailcove.instance.close()` sends, saves and lets go of the handlers.

## Help and feedback


- **Docs:** [tailcove.dev/docs/sending-logs/flutter](https://tailcove.dev/docs/sending-logs/flutter)
- **Bugs and feature requests:** [open an issue](https://github.com/tailcove/flutter/issues/new/choose)
- **Security problems:** please email **security@tailcove.dev** instead of opening a public issue.

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/footer-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/footer-light.svg">
  <img alt="Tailcove." src="https://raw.githubusercontent.com/tailcove/.github/main/profile/assets/packages/footer-dark.svg" width="100%">
</picture>

<p align="center">
  <a href="https://tailcove.dev/docs/sending-logs/flutter">Documentation</a> &nbsp;·&nbsp;
  <a href="https://tailcove.dev/register">Get started free</a> &nbsp;·&nbsp;
  <a href="https://pub.dev/packages/tailcove_flutter">View on pub.dev</a>
</p>
