import 'package:flutter/material.dart';

import '../app_theme.dart';

void showGameMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppTheme.navBackground,
      content: Text(
        message,
        style: context.type.body.copyWith(color: Colors.white),
      ),
    ),
  );
}
