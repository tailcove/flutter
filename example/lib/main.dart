import 'package:flutter/material.dart';
import 'package:tailcove_flutter/tailcove_flutter.dart';

void main() {
  Tailcove.runApp(
    const TailcoveOptions(appKey: 'tca_your_app_key', appId: 'com.example.shop', release: '1.0.0'),
    () => runApp(const ExampleApp()),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [TailcoveNavigatorObserver()],
      home: Scaffold(
        appBar: AppBar(title: const Text('Tailcove example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => Tailcove.instance.info('Button tapped', {'screen': 'home'}),
                child: const Text('Send a log'),
              ),
              ElevatedButton(
                onPressed: () => throw StateError('Something went wrong'),
                child: const Text('Throw an error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
