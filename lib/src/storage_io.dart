import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

TailcoveStorage applicationSupportStorage() => _FileStorage();

/// `tailcove_queue.json` in the application support directory, written whole and atomically (temp file, then rename).
class _FileStorage implements TailcoveStorage {
  Future<File>? _file;

  Future<File> get _resolved =>
      _file ??= getApplicationSupportDirectory().then((dir) => File('${dir.path}/tailcove_queue.json'));

  @override
  Future<String?> read() async {
    final file = await _resolved;

    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String? value) async {
    final file = await _resolved;

    if (value == null) {
      if (await file.exists()) {
        await file.delete();
      }

      return;
    }

    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    await temp.rename(file.path);
  }
}
