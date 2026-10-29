import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import 'api.dart';

Future<String?> captureFace() async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.front,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 80,
    requestFullMetadata: false,
  );
  if (photo == null) return null;
  final bytes = await photo.readAsBytes();
  if (bytes.length > 2 * 1024 * 1024) {
    throw const ApiException('Ảnh quá 2 MiB. Chụp lại với kích thước nhỏ hơn.');
  }
  return base64Encode(bytes);
}
