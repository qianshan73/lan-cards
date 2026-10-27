import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LanCardsApp(controller: AppController()));
}
