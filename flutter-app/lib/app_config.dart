import 'package:flutter/material.dart';
import 'package:besser_bahn/home/home_page.dart'; // Import HomePage

class SplitTicketApp extends StatelessWidget {
  const SplitTicketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Besser Bahn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEC0016), // DB Red
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEC0016), // DB Red
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}