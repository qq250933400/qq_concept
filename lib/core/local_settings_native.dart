import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_settings.dart';

const _keyName = 'local_database_key_v1';
const _dataFolder = 'qq_concept_data';

Uint8List _keyBytes(String key) => Uint8List.fromList([
  for (var i = 0; i < key.length; i += 2)
    int.parse(key.substring(i, i + 2), radix: 16),
]);

String _encrypt(String key, String value, List<String> context) {
  final random = Random.secure();
  final nonce = Uint8List.fromList(
    List.generate(12, (_) => random.nextInt(256)),
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(_keyBytes(key)),
        128,
        nonce,
        Uint8List.fromList(utf8.encode(jsonEncode(context))),
      ),
    );
  final encrypted = cipher.process(Uint8List.fromList(utf8.encode(value)));
  return 'v1:${base64Encode([...nonce, ...encrypted])}';
}

String _decrypt(String key, String value, List<String> context) {
  if (!value.startsWith('v1:')) throw const FormatException('本地数据加密格式无效');
  final bytes = base64Decode(value.substring(3));
  if (bytes.length < 28) throw const FormatException('本地加密数据不完整');
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(_keyBytes(key)),
        128,
        Uint8List.fromList(bytes.sublist(0, 12)),
        Uint8List.fromList(utf8.encode(jsonEncode(context))),
      ),
    );
  return utf8.decode(cipher.process(Uint8List.fromList(bytes.sublist(12))));
}

Future<QLocalStore?> openLocalStore(String defaultServer) async {
  final support = await getApplicationSupportDirectory();
  final cache = await getApplicationCacheDirectory();
  final settingsFile = path.join(support.path, 'settings.sqlite');
  final secure = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();
  var key = await secure.read(key: _keyName);
  if (key == null) {
    if (File(settingsFile).existsSync()) {
      throw StateError('本地数据库密钥丢失，无法打开设置');
    }
    final random = Random.secure();
    key = List.generate(
      32,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await secure.write(key: _keyName, value: key);
    if (await secure.read(key: _keyName) != key) {
      throw StateError('无法保存本地数据库密钥');
    }
  }
  return QSqliteLocalStore.open(
    settingsFile: settingsFile,
    defaultDirectory: path.join(cache.path, _dataFolder),
    defaultServer: defaultServer,
    key: key,
    restoreDirectory: Platform.isMacOS
        ? (bookmark) async {
            await const MethodChannel('qq_concept/windows').invokeMethod<void>(
              'restoreDataDirectory',
              {'bookmark': bookmark},
            );
          }
        : null,
  );
}

class QSqliteLocalStore implements QLocalStore {
  QSqliteLocalStore._(
    this._settingsDb,
    this._dataDb,
    this._key,
    this._settings,
  );

  final Database _settingsDb;
  Database _dataDb;
  final String _key;
  QLocalSettings _settings;

  static Future<QSqliteLocalStore> open({
    required String settingsFile,
    required String defaultDirectory,
    required String defaultServer,
    required String key,
    Future<void> Function(String bookmark)? restoreDirectory,
  }) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw StateError('本地数据库密钥无效');
    }
    Directory(path.dirname(settingsFile)).createSync(recursive: true);
    final settingsDb = _openDb(settingsFile);
    try {
      settingsDb.execute(
        'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      final values = <String, String>{
        for (final row in settingsDb.select('SELECT key, value FROM settings'))
          row['key'] as String: _decrypt(key, row['value'] as String, [
            'settings',
            row['key'] as String,
          ]),
      };
      if (values.isEmpty) {
        settingsDb.execute('INSERT INTO settings (key, value) VALUES (?, ?)', [
          'key_check',
          _encrypt(key, 'qq-local-v1', ['settings', 'key_check']),
        ]);
      } else if (values['key_check'] != 'qq-local-v1') {
        throw StateError('本地数据库密钥验证失败');
      }
      final optionsRaw = jsonDecode(values['options'] ?? '{}');
      if (optionsRaw is! Map) throw const FormatException('本地设置格式无效');
      final options = <String, bool>{};
      for (final entry in optionsRaw.entries) {
        if (entry.key is String && entry.value is bool) {
          options[entry.key as String] = entry.value as bool;
        }
      }
      final settings = QLocalSettings(
        server: values['server'] ?? defaultServer,
        dataDirectory: values['data_directory'] ?? defaultDirectory,
        options: options,
        directoryBookmark: values['directory_bookmark'],
      );
      if (settings.directoryBookmark != null && restoreDirectory != null) {
        await restoreDirectory(settings.directoryBookmark!);
      }
      final dataDb = _openData(settings.dataDirectory, key);
      return QSqliteLocalStore._(settingsDb, dataDb, key, settings);
    } catch (_) {
      settingsDb.close();
      rethrow;
    }
  }

  static Database _openDb(String file) {
    final db = sqlite3.open(file);
    try {
      db.select('SELECT count(*) FROM sqlite_master');
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static Database _openData(String directory, String key) {
    Directory(directory).createSync(recursive: true);
    final db = _openDb(path.join(directory, 'data.sqlite'));
    try {
      db.execute(
        'CREATE TABLE IF NOT EXISTS cache (server TEXT NOT NULL, user_id TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(server, user_id, kind, id))',
      );
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  @override
  QLocalSettings get settings => _settings;

  @override
  Future<void> save(QLocalSettings settings) async {
    final server = settings.server.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(server);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/v1')) {
      throw const FormatException('服务器地址须为 http(s)://主机:端口/v1');
    }
    final directory = path.normalize(settings.dataDirectory.trim());
    if (!path.isAbsolute(directory)) {
      throw const FormatException('数据目录必须是绝对路径');
    }
    final oldDirectory = path.normalize(_settings.dataDirectory);
    final changed = directory != oldDirectory;
    if (changed &&
        (path.isWithin(oldDirectory, directory) ||
            path.isWithin(directory, oldDirectory))) {
      throw const FormatException('新旧数据目录不能互相包含');
    }
    Database? nextDb;
    if (changed) {
      final target = Directory(directory);
      if (target.existsSync() && target.listSync().isNotEmpty) {
        throw const FormatException('新数据目录必须为空，避免覆盖已有数据');
      }
      target.createSync(recursive: true);
      _dataDb.close();
      try {
        _copyDirectory(Directory(oldDirectory), target);
        nextDb = _openData(directory, _key);
      } catch (_) {
        _dataDb = _openData(oldDirectory, _key);
        rethrow;
      }
    }
    final normalized = QLocalSettings(
      server: uri.toString(),
      dataDirectory: directory,
      options: Map.unmodifiable(settings.options),
      directoryBookmark: settings.directoryBookmark,
    );
    try {
      _settingsDb.execute('BEGIN IMMEDIATE');
      for (final entry in {
        'server': normalized.server,
        'data_directory': normalized.dataDirectory,
        'options': jsonEncode(normalized.options),
        if (normalized.directoryBookmark != null)
          'directory_bookmark': normalized.directoryBookmark!,
      }.entries) {
        _settingsDb.execute(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
          [
            entry.key,
            _encrypt(_key, entry.value, ['settings', entry.key]),
          ],
        );
      }
      if (normalized.directoryBookmark == null) {
        _settingsDb.execute(
          "DELETE FROM settings WHERE key = 'directory_bookmark'",
        );
      }
      _settingsDb.execute('COMMIT');
    } catch (_) {
      _settingsDb.execute('ROLLBACK');
      if (nextDb != null) {
        nextDb.close();
        _dataDb = _openData(oldDirectory, _key);
      }
      rethrow;
    }
    if (nextDb != null) _dataDb = nextDb;
    _settings = normalized;
  }

  static void _copyDirectory(Directory from, Directory to) {
    for (final entry in from.listSync(followLinks: false)) {
      final destination = path.join(to.path, path.basename(entry.path));
      if (entry is File) {
        entry.copySync(destination);
      } else if (entry is Directory) {
        final child = Directory(destination)..createSync();
        _copyDirectory(entry, child);
      } else {
        throw FileSystemException('数据目录包含不支持迁移的链接', entry.path);
      }
    }
  }

  @override
  void cache(
    String server,
    String userId,
    String kind,
    String id,
    Object data,
  ) {
    _dataDb.execute(
      'INSERT OR REPLACE INTO cache (server, user_id, kind, id, body) VALUES (?, ?, ?, ?, ?)',
      [
        server,
        userId,
        kind,
        id,
        _encrypt(_key, jsonEncode(data), ['cache', server, userId, kind, id]),
      ],
    );
  }

  @override
  void close() {
    _dataDb.close();
    _settingsDb.close();
  }
}
