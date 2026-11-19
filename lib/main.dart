import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MapAgentApp());
}

class MapAgentApp extends StatelessWidget {
  const MapAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Map Agent',
      debugShowCheckedModeBanner: false,
      theme: appLightTheme(),
      darkTheme: appDarkTheme(),
      home: const HomeScreen(),
    );
  }
}
