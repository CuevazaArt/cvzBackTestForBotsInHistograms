import 'package:flutter/material.dart';
import 'theme/dark_theme.dart';
import 'screens/home_screen.dart';

class BacktesterApp extends StatelessWidget {
  const BacktesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Backtester',
      debugShowCheckedModeBanner: false,
      theme: darkTheme(),
      home: const HomeScreen(),
    );
  }
}
