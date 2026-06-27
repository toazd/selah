import 'dart:io';

import 'package:path/path.dart' as path;

class LinuxConfigPaths {
  static const String _snapRealHomeKey = 'SNAP_REAL_HOME';
  static const String _homeKey = 'HOME';

  static String homeDirectory({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final snapRealHome = env[_snapRealHomeKey];
    if (snapRealHome != null && snapRealHome.isNotEmpty) {
      return snapRealHome;
    }

    return env[_homeKey] ?? '';
  }

  static String selahConfigDirectory({Map<String, String>? environment}) {
    return path.join(
        homeDirectory(environment: environment), '.config', 'selah');
  }
}
