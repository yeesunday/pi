import 'package:flutter/material.dart';

IconData pluginIcon(String name) => switch (name) {
  'check_circle' => Icons.check_circle_rounded,
  'celebration' => Icons.celebration_rounded,
  'edit_note' => Icons.edit_note_rounded,
  'notifications' => Icons.notifications_active_rounded,
  'repeat' => Icons.repeat_rounded,
  _ => Icons.extension_rounded,
};
