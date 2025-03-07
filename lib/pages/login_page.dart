import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/text/button.dart';
import 'package:safe_pulse/text/field.dart';
import 'package:safe_pulse/text/image.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controllers
  final TextEditingController userController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false; // ✅ Loading state

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.setLanguageCode('en'); 
  }

  @override
  void dispose() {
    userController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Sign in method
  void userIn() async {
    setState(() => isLoading = true); // Show loading indicator

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: userController.text.trim(),
        password: passwordController.text.trim(),
      );


      // Navigate to Home Page
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/new');
      }
    }on FirebaseAuthException catch (e) {
    String message;
    if (e.code == 'user-not-found') {
      message = "No user found with this email.";
    } else if (e.code == 'wrong-password') {
      message = "Incorrect password.";
    } else {
      message = "Something went wrong. Please try again.";
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  } finally {
    if (mounted) {
      setState(() => isLoading = false); // Hide loading indicator
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 50),

                // App name
                const Text(
                  "Safe Pulse",
                  style: TextStyle(
                    fontSize: 40,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 30),

                const Text(
                  "Welcome back, you've been missed!",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 25),

                Field(
                  controller: userController,
                  obscureText: false,
                  hintText: "Email",
                ),

                const SizedBox(height: 15),

                Field(
                  controller: passwordController,
                  obscureText: true,
                  hintText: "Password",
                ),

                const SizedBox(height: 10),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        "Forgot Password?",
                        style: TextStyle(
                          color: Colors.blue,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // Sign in button
                isLoading
                    ? const CircularProgressIndicator() 
                    : Button(onTap: userIn),

                const SizedBox(height: 30),

                // Sign in method divider
                const Padding(
                  padding:  EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(color: Colors.black),
                      ),
                       Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text("Or continue with"),
                      ),
                      Expanded(
                        child: Divider(color: Colors.black),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 50),

                // Social login buttons
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ImageText(imagePath: 'assets/google.png'),
                    SizedBox(width: 20),
                    ImageText(imagePath: 'assets/apple.png'),
                  ],
                ),

                const SizedBox(height: 30),

                // Register now
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Not a member?"),
                    SizedBox(width: 4),
                    Text(
                      "Register now",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

