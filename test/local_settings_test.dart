import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:qq_concept/core/local_settings.dart';
import 'package:qq_concept/core/local_settings_native.dart'
    show QSqliteLocalStore;
import 'package:qq_concept/screens/settings_screen.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('随机密钥生成一次并从安全存储恢复', () async {
    final root = Directory.systemTemp.createTempSync('qq-key-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
          return path.join(root.path, 'support');
        case 'getApplicationCacheDirectory':
          return path.join(root.path, 'cache');
        default:
          throw MissingPluginException(call.method);
      }
    });
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      FlutterSecureStorage.setMockInitialValues({});
      root.deleteSync(recursive: true);
    });
    var store = await openLocalStore('http://localhost/v1');
    final secure = FlutterSecureStorage(
      mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
    );
    final key = await secure.read(key: 'local_database_key_v1');
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    store!.close();
    store = await openLocalStore('http://localhost/v1');
    expect(await secure.read(key: 'local_database_key_v1'), key);
    store!.close();
    FlutterSecureStorage.setMockInitialValues({});
    await expectLater(openLocalStore('http://localhost/v1'), throwsStateError);
  });

  testWidgets('设置窗口可以保存服务器地址', (tester) async {
    final root = Directory.systemTemp.createTempSync('qq-settings-ui-');
    final store = await QSqliteLocalStore.open(
      settingsFile: path.join(root.path, 'settings.sqlite'),
      defaultDirectory: path.join(root.path, 'cache'),
      defaultServer: 'http://localhost:3000/v1',
      key: 'ef' * 32,
    );
    addTearDown(() {
      store.close();
      root.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(268, 645);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(localStore: store)),
    );
    await tester.tap(find.text('服务器与存储位置'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-address')),
      'https://other.example/v1',
    );
    await tester.tap(find.byKey(const ValueKey('save-local-settings')));
    await tester.pumpAndSettle();
    expect(store.settings.server, 'https://other.example/v1');
    expect(tester.takeException(), isNull);
  });

  test('本地设置加密保存，迁移缓存后可重新打开且不会覆盖已有目录', () async {
    final root = await Directory.systemTemp.createTemp('qq-local-test-');
    addTearDown(() => root.deleteSync(recursive: true));
    final settingsFile = path.join(root.path, 'config', 'settings.sqlite');
    final original = path.join(root.path, 'cache');
    final target = path.join(root.path, 'moved');
    final key = 'ab' * 32;
    var store = await QSqliteLocalStore.open(
      settingsFile: settingsFile,
      defaultDirectory: original,
      defaultServer: 'http://localhost:3000/v1',
      key: key,
    );
    store.cache('http://localhost:3000/v1', 'user', 'message', 'm1', {
      'text': 'private-message',
    });
    File(path.join(original, 'resource.txt')).writeAsStringSync('resource');
    await store.save(
      QLocalSettings(
        server: 'https://new.example/v1',
        dataDirectory: target,
        options: {'sound': false},
      ),
    );
    expect(
      File(path.join(target, 'resource.txt')).readAsStringSync(),
      'resource',
    );
    expect(File(path.join(original, 'data.sqlite')).existsSync(), isTrue);
    final occupied = Directory(path.join(root.path, 'occupied'))..createSync();
    File(path.join(occupied.path, 'keep')).writeAsStringSync('keep');
    await expectLater(
      store.save(
        QLocalSettings(
          server: 'https://new.example/v1',
          dataDirectory: occupied.path,
        ),
      ),
      throwsFormatException,
    );
    expect(store.settings.dataDirectory, target);
    expect(File(path.join(occupied.path, 'keep')).readAsStringSync(), 'keep');
    await expectLater(
      store.save(QLocalSettings(server: 'file:///v1', dataDirectory: target)),
      throwsFormatException,
    );
    store.close();

    final configDb = sqlite3.open(settingsFile);
    final rawServer =
        configDb
                .select("SELECT value FROM settings WHERE key='server'")
                .single['value']
            as String;
    expect(rawServer, isNot(contains('new.example')));
    configDb.close();
    final dataDb = sqlite3.open(path.join(target, 'data.sqlite'));
    final rawMessage =
        dataDb.select('SELECT body FROM cache').single['body'] as String;
    expect(rawMessage, isNot(contains('private-message')));
    dataDb.close();

    await expectLater(
      QSqliteLocalStore.open(
        settingsFile: settingsFile,
        defaultDirectory: original,
        defaultServer: 'http://localhost/v1',
        key: 'cd' * 32,
      ),
      throwsA(isA<Exception>()),
    );
    store = await QSqliteLocalStore.open(
      settingsFile: settingsFile,
      defaultDirectory: original,
      defaultServer: 'http://localhost/v1',
      key: key,
    );
    expect(store.settings.server, 'https://new.example/v1');
    expect(store.settings.dataDirectory, target);
    expect(store.settings.options['sound'], isFalse);
    store.close();
  });
}
