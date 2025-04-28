import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/navigate.dart';
import 'package:safe_pulse/pages/login/login_or_register.dart';

class UserCheckPage extends StatelessWidget {
  const UserCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Debug print to verify stream updates
          print("Auth state changed: ${snapshot.connectionState}, hasData: ${snapshot.hasData}");
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else {
            if (snapshot.hasData) {
              print("User authenticated: ${snapshot.data?.uid}");
              // Force a rebuild with a small delay to ensure UI updates
              Future.microtask(() => {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const Navigate()),
                )
              });
              return const Center(child: CircularProgressIndicator());
            } else {
              return const LoginOrRegister();
            }
          }
        },
      ),
    );
  }
}