import 'package:flutter/widgets.dart';
import 'package:tailcove_flutter/tailcove_flutter.dart';

void main() {
  Tailcove.runApp(
    const TailcoveOptions(
        appKey: 'tca_your_app_key',
        appId: 'com.example.shop',
        release: '1.0.0'),
    () => runApp(const ExampleApp()),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF0F172A),
      textStyle: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16),
      navigatorObservers: [TailcoveNavigatorObserver()],
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, _, __) => builder(context)),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Button(
              label: 'Send a log',
              onTap: () =>
                  Tailcove.instance.info('Button tapped', {'screen': 'home'}),
            ),
            const SizedBox(height: 16),
            _Button(
                label: 'Throw an error',
                onTap: () => throw StateError('Something went wrong')),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF97316),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label),
      ),
    );
  }
}
