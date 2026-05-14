import 'package:flutter/material.dart';
import 'package:backtester_shell/screens/home_screen.dart';
import 'package:backtester_shell/services/api_service.dart';

class BacktesterApp extends StatelessWidget {
  const BacktesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Backtester Shell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF131722),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF26a69a),
          secondary: Color(0xFFef5350),
          surface: Color(0xFF1E222D),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E222D),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFD9D9D9),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFD9D9D9)),
          bodySmall: TextStyle(color: Color(0xFF787B86)),
        ),
        dividerColor: const Color(0xFF2B2B43),
        cardColor: const Color(0xFF1E222D),
      ),
      home: HomeScreen(apiService: ApiService()),
    );
  }
}
