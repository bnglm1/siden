// permissions_manager.dart
import 'package:permission_handler/permission_handler.dart';

class PermissionsManager {
  // Kamera ve mikrofon izinlerini kontrol et ve iste
  static Future<bool> requestCameraAndMicrophonePermissions() async {
    try {
      // Kamera ve mikrofon izinlerini aynı anda iste
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      // Her iki iznin de verilip verilmediğini kontrol et
      bool cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      bool microphoneGranted =
          statuses[Permission.microphone]?.isGranted ?? false;

      print('Kamera izni: $cameraGranted');
      print('Mikrofon izni: $microphoneGranted');

      return cameraGranted && microphoneGranted;
    } catch (e) {
      print('İzin isteme hatası: $e');
      return false;
    }
  }

  // Sadece mikrofon iznini kontrol et (sesli arama için)
  static Future<bool> requestMicrophonePermission() async {
    try {
      PermissionStatus status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      print('Mikrofon izni hatası: $e');
      return false;
    }
  }

  // İzinlerin durumunu kontrol et
  static Future<Map<String, bool>> checkPermissions() async {
    bool cameraGranted = await Permission.camera.isGranted;
    bool microphoneGranted = await Permission.microphone.isGranted;

    return {
      'camera': cameraGranted,
      'microphone': microphoneGranted,
    };
  }
}
