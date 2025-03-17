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
  bool isLoading = false; //

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
    showDialog(
      context: context, 
      builder: (context) => const Center(child: CircularProgressIndicator(),),
      );

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: userController.text,
        password: passwordController.text,
      );

      //pop the loading circle
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      //pop the loading circle  
      Navigator.pop(context);
      if (e.code == 'user-not-found') {
        wrongEmailMessage();
      } else if (e.code == 'wrong-password') {
        wrongEmailMessage();
      }
    }
  }

  void wrongEmailMessage() {
    showDialog(
      context: context, 
      builder: (context){
        return const AlertDialog(
          backgroundColor: Colors.blue,
          title: Center(
            child: Text(
              "Wrong Email",
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );
  }


  void wrongPasswordMessage() {
    showDialog(
      context: context, 
      builder: (context){
        return const AlertDialog(
          backgroundColor: Colors.blue,
          title: Center(
            child: Text(
              "Wrong Password",
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );
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