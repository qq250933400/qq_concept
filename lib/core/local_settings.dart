import 'local_settings_stub.dart'
    if (dart.library.io) 'local_settings_native.dart'
    as implementation;

class QLocalSettings {
  const QLocalSettings({
    required this.server,
    required this.dataDirectory,
    this.options = const {},
    this.directoryBookmark,
  });

  final String server;
  final String dataDirectory;
  final Map<String, bool> options;
  final String? directoryBookmark;
}

abstract class QLocalStore {
  QLocalSettings get settings;
  Future<void> save(QLocalSettings settings);
  void cache(String server, String userId, String kind, String id, Object data);
  void close();
}

Future<QLocalStore?> openLocalStore(String defaultServer) =>
    implementation.openLocalStore(defaultServer);
