import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/home.dart';
import 'package:safe_pulse/pages/login_or_register.dart';

class UserCheckPage extends StatelessWidget {
  const UserCheckPage({Key? key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          } else {
            if (snapshot.hasData) {
              return const Home();
            } else {
              return const LoginOrRegister();
            }
          }
        },
      ),
    );
  }
}
