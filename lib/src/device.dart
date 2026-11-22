import 'device_stub.dart' if (dart.library.io) 'device_io.dart' as platform;

/// What every line carries about the device: the OS and its version.
Map<String, Object?> deviceContext() => platform.deviceContext();

/// The OS name, used as the line's host.
String osName() => platform.osName();
