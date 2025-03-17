import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/home.dart';
import 'package:safe_pulse/pages/login_or_register.dart';

class UserCheckPage extends StatelessWidget {
  const UserCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            //user log
            return const Home();
            //not log
          } else {
            return  const LoginOrRegister();
          }
        }
        ,)
    );
  }
}