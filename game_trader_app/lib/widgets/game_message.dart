import 'package:flutter/material.dart';

void showGameMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF0f172a),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
    ),
  );
}
