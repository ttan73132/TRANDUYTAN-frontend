import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const backgroundChoices = <(String, Color)>[
  ('Mây trắng', Color(0xFFF3F6FA)),
  ('Xanh biển', Color(0xFFE8F2FF)),
  ('Xanh lá', Color(0xFFECF5EF)),
  ('Cát ấm', Color(0xFFFAF1E3)),
  ('Hồng nhạt', Color(0xFFFAECEE)),
];

class AppPreferences {
  final FlutterSecureStorage storage;
  double textScale = 1;
  int backgroundIndex = 0;
  Map<String, String> profile = {};
  AppPreferences(this.storage);
  Color get background => backgroundChoices[backgroundIndex].$2;

  Future<void> load() async {
    final raw = await storage.read(key: 'appearance_v1');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map;
      final scale = (data['textScale'] as num?)?.toDouble() ?? 1;
      textScale = scale.isFinite ? scale.clamp(.85, 1.4) : 1;
      backgroundIndex = ((data['background'] as num?)?.toInt() ?? 0).clamp(
        0,
        backgroundChoices.length - 1,
      );
    } on FormatException {
      // A damaged preference must not prevent account sign-in.
    } on TypeError {
      // Ignore incompatible preferences from older installations.
    }
  }

  Future<void> appearance(double scale, int background) async {
    final nextScale = scale.isFinite ? scale.clamp(.85, 1.4) : 1.0;
    final nextBackground = background.clamp(0, backgroundChoices.length - 1);
    await storage.write(
      key: 'appearance_v1',
      value: jsonEncode({'textScale': nextScale, 'background': nextBackground}),
    );
    textScale = nextScale;
    backgroundIndex = nextBackground;
  }

  String _profileKey(String origin, String id) =>
      'profile_v1_${Uri.encodeComponent(origin)}_$id';

  Future<void> loadProfile(String origin, String id) async {
    profile = {};
    final raw = await storage.read(key: _profileKey(origin, id));
    if (raw == null) return;
    try {
      profile = Map<String, String>.from(jsonDecode(raw) as Map);
    } on FormatException {
      profile = {};
    } on TypeError {
      profile = {};
    }
  }

  Future<void> saveProfile(
    String origin,
    String id,
    Map<String, String> data,
  ) async {
    final safe = {
      for (final key in ['fullName', 'phone', 'department', 'position', 'bio'])
        if (data[key] != null) key: data[key]!.trim(),
    };
    await storage.write(key: _profileKey(origin, id), value: jsonEncode(safe));
    profile = safe;
  }
}
