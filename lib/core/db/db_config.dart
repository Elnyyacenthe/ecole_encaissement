class DbConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String dbName;

  const DbConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.dbName,
  });

  /// Built-in settings used when nothing else is configured. The database
  /// user is created by the bundled server on first start ([EmbeddedServer]);
  /// an empty [host] means "find the server on the local network".
  /// Port 3307 avoids clashing with any MySQL already installed on 3306.
  static const DbConfig defaults = DbConfig(
    host: '',
    port: 3307,
    user: 'cosbimp',
    password: 'Cosbimp@2026',
    dbName: 'cosbimp_scolarite',
  );

  bool get hasHost => host.isNotEmpty;

  DbConfig copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? dbName,
  }) {
    return DbConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      dbName: dbName ?? this.dbName,
    );
  }
}
