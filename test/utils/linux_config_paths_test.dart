import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:selah/utils/linux_config_paths.dart';

void main() {
  test('uses SNAP_REAL_HOME for canonical Linux config inside snaps', () {
    final configPath = LinuxConfigPaths.selahConfigDirectory(
      environment: {
        'HOME': '/home/tester/snap/selah/current',
        'SNAP_REAL_HOME': '/home/tester',
      },
    );

    expect(configPath, path.join('/home/tester', '.config', 'selah'));
  });

  test('falls back to HOME outside snaps', () {
    final configPath = LinuxConfigPaths.selahConfigDirectory(
      environment: {'HOME': '/home/tester'},
    );

    expect(configPath, path.join('/home/tester', '.config', 'selah'));
  });
}
