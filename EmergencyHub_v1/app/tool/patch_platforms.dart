// Run once after `flutter create .` :   dart run tool/patch_platforms.dart
//
// Adds what the app needs on the native platforms:
//   Android: INTERNET + location + notification permissions, and cleartext HTTP (so the app can
//            talk to your local http:// server during development).
//   iOS:     location usage text and permission for local-network HTTP.
import 'dart:io';

void main() {
  _android();
  _ios();
  stdout.writeln('Done. (Safe to run again.)');
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stdout.writeln('Android: manifest not found – skipped (run `flutter create .` first).');
    return;
  }
  var s = f.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
  ];
  final missing = perms.where((p) => !s.contains('"$p"')).toList();
  if (missing.isNotEmpty) {
    final add = missing.map((p) => '    <uses-permission android:name="$p"/>\n').join();
    s = s.replaceFirst('<application', '$add    <application');
  }
  if (!s.contains('usesCleartextTraffic')) {
    s = s.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }
  f.writeAsStringSync(s);
  stdout.writeln('Android: manifest updated.');
}

void _ios() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) {
    stdout.writeln('iOS: Info.plist not found – skipped.');
    return;
  }
  var s = f.readAsStringSync();
  final add = StringBuffer();
  if (!s.contains('NSLocationWhenInUseUsageDescription')) {
    add.writeln('\t<key>NSLocationWhenInUseUsageDescription</key>');
    add.writeln('\t<string>Used to attach your location to emergency reports.</string>');
  }
  if (!s.contains('NSAppTransportSecurity')) {
    add.writeln('\t<key>NSAppTransportSecurity</key>');
    add.writeln('\t<dict>');
    add.writeln('\t\t<key>NSAllowsLocalNetworking</key>');
    add.writeln('\t\t<true/>');
    add.writeln('\t</dict>');
  }
  if (add.isNotEmpty) {
    final i = s.lastIndexOf('</dict>');
    s = s.substring(0, i) + add.toString() + s.substring(i);
    f.writeAsStringSync(s);
  }
  stdout.writeln('iOS: Info.plist updated.');
}
