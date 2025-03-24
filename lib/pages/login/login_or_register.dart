import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/login/login_page.dart';
import 'package:safe_pulse/pages/login/register_page.dart';

class LoginOrRegister extends StatefulWidget {
  const LoginOrRegister({super.key});

  @override
  State<LoginOrRegister> createState() => _LoginOrRegisterState();
}

class _LoginOrRegisterState extends State<LoginOrRegister> {
  bool showLogin = true;

  void toggleScreens() {
    setState(() {
      showLogin = !showLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (showLogin) {
      return LoginPage(onTap: toggleScreens);
    } else {
      return RegisterPage(onTap: toggleScreens);
    }
  }
}
