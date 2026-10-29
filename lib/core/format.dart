import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
DateTime vnTime(String value) =>
    DateTime.parse(value).toUtc().add(const Duration(hours: 7));
String dateTime(dynamic value) => value == null
    ? 'Chưa ghi nhận'
    : DateFormat('dd/MM/yyyy · HH:mm').format(vnTime(value.toString()));
String timeOnly(dynamic value) => value == null
    ? '--:--'
    : DateFormat('HH:mm').format(vnTime(value.toString()));
String dateOnly(dynamic value) => value == null
    ? ''
    : DateFormat('dd/MM/yyyy').format(vnTime(value.toString()));
String statusLabel(String? value) =>
    const {
      'Draft': 'Bản nháp',
      'Pending': 'Chờ duyệt',
      'Approved': 'Đã duyệt',
      'Rejected': 'Từ chối',
      'Late': 'Đi muộn',
      'On Time': 'Đúng giờ',
      'Checked Out': 'Đã ra ca',
      'ACTIVE': 'Hoạt động',
      'INACTIVE': 'Vô hiệu hóa',
      'ADMIN': 'Quản trị viên',
      'EMPLOYEE': 'Nhân viên',
      'admin': 'Quản trị viên',
      'manager': 'Quản lý',
      'employee': 'Nhân viên',
      'pending': 'Chờ duyệt',
      'active': 'Hoạt động',
      'suspended': 'Tạm khóa',
      'approved': 'Đã duyệt',
      'rejected': 'Từ chối',
      'scheduled': 'Đã phân ca',
      'in_progress': 'Trong ca',
      'completed': 'Hoàn thành',
      'draft': 'Bản nháp',
      'submitted': 'Đã gửi',
      'acknowledged': 'Đã xác nhận',
      'open': 'Chưa xác nhận',
      'understood': 'Đã hiểu',
      'clarify': 'Cần làm rõ',
    }[value] ??
    value ??
    '';
