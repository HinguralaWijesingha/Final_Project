import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/text/button.dart';
import 'package:safe_pulse/text/field.dart';

class RegisterPage extends StatefulWidget {
  final Function()? onTap;
  const RegisterPage({super.key, required this.onTap});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController userController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmpasswordController =
      TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool isLoading = false;

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

  // Sign Up method
  void userUp() async {
    try {
      if (passwordController.text == confirmpasswordController.text) {
        UserCredential userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: userController.text.trim(),
          password: passwordController.text.trim(),
        );

        // Add user data to Firestore
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(userCredential.user!.uid)
            .set({
          'name': nameController.text,
          'email': userController.text,
          'phonenumber': phoneController.text
        });
      } else {
        showErrormessage("Passwords do not match");
      }
    } on FirebaseAuthException catch (e) {
      showErrormessage(e.code);
    }
  }

  void showErrormessage(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.blue,
          title: Center(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void wrongPasswordMessage() {
    showDialog(
      context: context,
      builder: (context) {
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                // logo
                Image.asset(
                  'assets/lo23.png',
                  width: 100,
                  height: 100,
                ),

                const SizedBox(height: 15),

                Text(
                  "create your account here.".toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 15),

                Field(
                  controller: nameController,
                  obscureText: false,
                  hintText: "Enter Your Name",
                ),

                const SizedBox(height: 15),

                Field(
                  controller: userController,
                  obscureText: false,
                  hintText: "Enter Your Email",
                ),

                const SizedBox(height: 15),

                Field(
                  controller: passwordController,
                  obscureText: true,
                  hintText: "Enter Your Password",
                ),

                const SizedBox(height: 15),

                Field(
                  controller: confirmpasswordController,
                  obscureText: true,
                  hintText: "Confirm Your Password",
                ),

                const SizedBox(height: 15),

                Field(
                  controller: phoneController,
                  obscureText: false,
                  hintText: "Enter Your Phone Number",
                ),

                const SizedBox(height: 20),

                // Sign in button
                Button(
                  text: isLoading ? "Signing Up..." : "Sign Up", 
                  onTap:  isLoading ? null : userUp),

                const SizedBox(height: 20),

                // Login now
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Have an account"),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        // Navigate back to login screen
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Login Now",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
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
