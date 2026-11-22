import 'dart:io';

Map<String, Object?> deviceContext() {
  try {
    return {
      'os': {'name': Platform.operatingSystem, 'version': Platform.operatingSystemVersion},
      'runtime': {'name': 'dart', 'version': Platform.version.split(' ').first},
    };
  } catch (_) {
    return {};
  }
}

String osName() {
  try {
    return Platform.operatingSystem;
  } catch (_) {
    return 'mobile';
  }
}
