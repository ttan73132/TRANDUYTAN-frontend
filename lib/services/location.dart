import 'package:geolocator/geolocator.dart';

import 'api.dart';

Future<Position> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const ApiException(
      'GPS đang tắt. Bật vị trí trên điện thoại rồi thử lại.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const ApiException(
      'Quyền vị trí bị chặn. Mở cài đặt ứng dụng để cấp lại quyền.',
    );
  }
  if (permission == LocationPermission.denied) {
    throw const ApiException(
      'Cần cho phép truy cập vị trí khi sử dụng ứng dụng.',
    );
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 25),
    ),
  );
  if (position.isMocked) {
    throw const ApiException(
      'Thiết bị đánh dấu vị trí giả lập. Cần dùng GPS thực.',
    );
  }
  if (position.accuracy <= 0 || position.accuracy > 100) {
    throw const ApiException(
      'GPS chưa đủ chính xác (cần ≤100m). Ra nơi thoáng rồi thử lại.',
    );
  }
  return position;
}
