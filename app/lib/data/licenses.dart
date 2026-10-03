import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Adds bundled non-pub artifacts to Flutter's standard LicensePage.
/// Pub dependencies retain their automatically generated license entries.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    const notices = <String, List<String>>{
      'MODEL-NOTICE.txt': ['Mahjong YOLO model — provenance and status'],
      'mahjong-yolo-repository-MIT.txt': ['Mahjong-YOLO repository'],
      'AGPL-3.0.txt': ['Mahjong YOLO model — Ultralytics license context'],
      'onnxruntime-MIT.txt': ['ONNX Runtime'],
      'onnxruntime-ThirdPartyNotices.txt': ['ONNX Runtime third-party notices'],
      'NotoSansTC-OFL.txt': ['Noto Sans TC'],
      'Roboto-OFL.txt': ['Roboto'],
    };
    for (final entry in notices.entries) {
      final text = await rootBundle.loadString('assets/licenses/${entry.key}');
      yield LicenseEntryWithLineBreaks(entry.value, text);
    }
  });
}
