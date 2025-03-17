import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/login_page.dart';

class LoginOrRegister extends StatefulWidget {
  const LoginOrRegister({super.key});

  @override
  State<LoginOrRegister> createState() => _LoginOrRegisterState();
}

class LoginOrRegisterState extends State<LoginOrRegister> {
  bool isLogin = true;

  void togglePages() {
    setState(() {
      isLogin = !isLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLogin) {
      return  LoginPage(
        onTap: togglePages,
      );
    } else {
      return const RegisterPage();
    }
  }
}
