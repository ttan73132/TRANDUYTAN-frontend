import '../core/format.dart';

class AppUser {
  final Json values;
  AppUser(this.values);
  String get id => values['id'] as String;
  String get employeeId => (values['employee_id'] ?? id) as String;
  String get fullName => (values['fullName'] ?? values['full_name']) as String;
  bool get isAdmin => values['role'].toString().toLowerCase() == 'admin';
  bool get isManager => values['role'].toString().toLowerCase() == 'manager';
  bool get canManage => isAdmin || isManager;
  bool get isActive =>
      values['status'].toString().toLowerCase() == 'active' &&
      values['emailVerified'] != false;
  String get initial => fullName.trim().isEmpty
      ? 'T'
      : fullName.trim().substring(0, 1).toUpperCase();
}
