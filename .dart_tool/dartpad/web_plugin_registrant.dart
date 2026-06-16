// Flutter web plugin registrant file.
//
// Generated file. Do not edit.
//

// @dart = 2.13
// ignore_for_file: type=lint

import 'package:app_links_web/app_links_web.dart';
import 'package:connectivity_plus/src/connectivity_plus_web.dart';
import 'package:device_info_plus/src/device_info_plus_web.dart';
import 'package:file_picker/src/platform/web/file_picker_web.dart';
import 'package:flutter_keyboard_visibility_temp_fork/flutter_keyboard_visibility_web.dart';
import 'package:image_picker_for_web/image_picker_for_web.dart';
import 'package:package_info_plus/src/package_info_plus_web.dart';
import 'package:passkeys_web/passkeys_web.dart';
import 'package:permission_handler_html/permission_handler_html.dart';
import 'package:quill_native_bridge_web/quill_native_bridge_web.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:ua_client_hints/ua_client_hints_web.dart';
import 'package:url_launcher_web/url_launcher_web.dart';
import 'package:video_player_web/video_player_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerPlugins([final Registrar? pluginRegistrar]) {
  final Registrar registrar = pluginRegistrar ?? webPluginRegistrar;
  AppLinksPluginWeb.registerWith(registrar);
  ConnectivityPlusWebPlugin.registerWith(registrar);
  DeviceInfoPlusWebPlugin.registerWith(registrar);
  FilePickerWeb.registerWith(registrar);
  FlutterKeyboardVisibilityTempForkWeb.registerWith(registrar);
  ImagePickerPlugin.registerWith(registrar);
  PackageInfoPlusWebPlugin.registerWith(registrar);
  PasskeysWeb.registerWith(registrar);
  WebPermissionHandler.registerWith(registrar);
  QuillNativeBridgeWeb.registerWith(registrar);
  SharedPreferencesPlugin.registerWith(registrar);
  UaClientHintsWeb.registerWith(registrar);
  UrlLauncherPlugin.registerWith(registrar);
  VideoPlayerPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
