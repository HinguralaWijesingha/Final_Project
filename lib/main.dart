import 'package:flutter/material.dart';
import 'package:safe_pulse/onboarding/index.dart';
import 'package:safe_pulse/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async{
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final onboarding = prefs.getBool('onboarding') ?? false;
  runApp( MyApp( onboarding: onboarding,));
}

class MyApp extends StatelessWidget {
  final bool onboarding;
  const MyApp({super.key,  this.onboarding = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: onboarding ?  LoginPage() :   const OnboardingDisplay(),
    );
  }
}
