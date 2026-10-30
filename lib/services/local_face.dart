import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

const faceModelRevision = '48b10fa505aeb51fbd127fc60a5c660040e823b7';
const faceModelBytes = 38696353;
const faceModelSha =
    '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79';

List<double> normalizedFace(List<num> values) {
  if (values.length != 128 || values.any((n) => !n.isFinite)) {
    throw const FormatException('Mẫu khuôn mặt không hợp lệ.');
  }
  final length = sqrt(values.fold<double>(0, (sum, n) => sum + n * n));
  if (!length.isFinite || length < 1e-8) {
    throw const FormatException('Mẫu khuôn mặt rỗng hoặc không hợp lệ.');
  }
  return values.map((n) => n / length).toList();
}

double faceSimilarity(List<num> first, List<num> second) {
  final a = normalizedFace(first), b = normalizedFace(second);
  return List.generate(128, (i) => a[i] * b[i]).reduce((a, b) => a + b);
}

/// Motion is an obstacle to static photos, not a certified anti-spoof check.
class FaceChallenge {
  final List<double>? reference;
  final int direction;
  int stage = 0;
  List<double>? first;
  FaceChallenge({this.reference, int? direction})
    : direction = direction ?? (Random.secure().nextBool() ? 1 : -1);
  String get instruction => switch (stage) {
    0 => 'Nhìn thẳng vào camera',
    1 => 'Quay đầu nhẹ theo hướng mũi tên',
    _ => 'Nhìn thẳng lại để hoàn tất',
  };
  List<double>? observe(List<num> vector, double yaw) {
    if (!yaw.isFinite) return null;
    final candidate = normalizedFace(vector);
    final expected = reference ?? first;
    if (expected != null && faceSimilarity(expected, candidate) < .5) {
      stage = 0;
      first = null;
      throw const ApiException('Khuôn mặt chưa khớp. Nhìn thẳng và thử lại.');
    }
    final pose = stage == 1
        ? yaw * direction >= 14 && yaw.abs() <= 32
        : yaw.abs() <= 9;
    if (!pose) return null;
    if (stage == 0) first = candidate;
    stage++;
    if (stage < 3) return null;
    return normalizedFace(List.generate(128, (i) => first![i] + candidate[i]));
  }
}

class LocalFaceAccess {
  static const channel = MethodChannel('vn.nhom8.tranduytan/local_face');
  final FlutterSecureStorage storage;
  LocalFaceAccess({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'camera_face_v1'),
          );
  Future<void> enroll(List<num> template, String token) => storage.write(
    key: 'record',
    value: jsonEncode({'embedding': normalizedFace(template), 'token': token}),
  );
  Future<List<double>> template() async {
    final record = jsonDecode(await storage.read(key: 'record') ?? '{}') as Map;
    return normalizedFace(List<num>.from(record['embedding'] as List));
  }

  Future<String?> token() async {
    final record = jsonDecode(await storage.read(key: 'record') ?? '{}') as Map;
    return record['token'] as String?;
  }

  Future<void> saveToken(String token) async => enroll(await template(), token);
  Future<void> clear() => storage.delete(key: 'record');

  Future<String> prepare(void Function(double) progress) async {
    final folder = await getApplicationSupportDirectory();
    final file = File('${folder.path}/sface-$faceModelRevision.onnx');
    Future<bool> valid(File candidate) async =>
        await candidate.exists() &&
        await candidate.length() == faceModelBytes &&
        (await sha256.bind(candidate.openRead()).first).toString() ==
            faceModelSha;
    if (await valid(file)) return file.path;
    final partial = File('${file.path}.part');
    final client = http.Client();
    IOSink? sink;
    try {
      final response = await client
          .send(
            http.Request(
              'GET',
              Uri.parse(
                'https://media.githubusercontent.com/media/opencv/opencv_zoo/$faceModelRevision/models/face_recognition_sface/face_recognition_sface_2021dec.onnx',
              ),
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const ApiException(
          'Không tải được gói nhận diện mặt. Thử lại khi có mạng.',
        );
      }
      sink = partial.openWrite();
      var count = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        count += chunk.length;
        if (count > faceModelBytes) {
          throw const FormatException('Sai kích thước mô hình.');
        }
        sink.add(chunk);
        progress(count / faceModelBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!await valid(partial)) {
        throw const FormatException('Gói nhận diện không đúng SHA-256.');
      }
      if (await file.exists()) await file.delete();
      await partial.rename(file.path);
      return file.path;
    } finally {
      client.close();
      await sink?.close();
      if (await partial.exists()) await partial.delete();
    }
  }
}
