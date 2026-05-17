import 'package:flutter/material.dart';

class CvzBacktesterApp extends StatelessWidget {
  const CvzBacktesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CVZ Backtester',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('CVZ Backtester — Phase 0 scaffold complete'),
        ),
      ),
    );
  }
}
