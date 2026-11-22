import 'dart:async';
import 'dart:convert';

import 'storage.dart';

/// The lines waiting to be sent, oldest first, mirrored to storage so lines written offline, or just before a crash,
/// go out on the next launch. Lines leave only once the server took them (peek, send, then ack). Past [maxSize] the
/// oldest go first.
class PersistentQueue {
  PersistentQueue(this.maxSize, this._storage, this._onError) {
    _restored = _restore();
  }

  final int maxSize;
  final TailcoveStorage? _storage;
  final void Function(Object error) _onError;

  List<Map<String, Object?>> _lines = [];
  Timer? _saveTimer;
  late final Future<void> _restored;

  Future<void> get ready => _restored;

  int get length => _lines.length;

  void push(Map<String, Object?> line) {
    _lines.add(line);
    _trim();
    _scheduleSave();
  }

  List<Map<String, Object?>> peek(int count) => _lines.take(count).toList();

  /// Removes lines the server took, by identity, so lines dropped or added meanwhile shift nothing.
  void ack(List<Map<String, Object?>> batch) {
    final sent = Set<Map<String, Object?>>.identity()..addAll(batch);
    _lines = _lines.where((line) => !sent.contains(line)).toList();
    _scheduleSave();
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;

    final storage = _storage;

    if (storage == null) {
      return;
    }

    try {
      await storage.write(_lines.isEmpty ? null : jsonEncode(_lines));
    } catch (error) {
      _onError(error);
    }
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  Future<void> _restore() async {
    final storage = _storage;

    if (storage == null) {
      return;
    }

    try {
      final stored = await storage.read();
      final decoded = stored == null ? const [] : jsonDecode(stored);

      if (decoded is List) {
        final earlier = decoded
            .whereType<Map<String, Object?>>()
            .where((line) => line['message'] is String && line['level'] is String && line['ts'] is String)
            .toList();
        _lines = [...earlier, ..._lines];
        _trim();
      }
    } catch (error) {
      _onError(error);
    }
  }

  void _trim() {
    if (_lines.length > maxSize) {
      _lines.removeRange(0, _lines.length - maxSize);
    }
  }

  void _scheduleSave() {
    if (_storage == null || _saveTimer != null) {
      return;
    }

    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveTimer = null;
      save();
    });
  }
}
