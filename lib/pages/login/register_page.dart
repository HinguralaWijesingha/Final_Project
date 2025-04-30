import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/navigate.dart';
import 'package:safe_pulse/text/button.dart';
import 'package:safe_pulse/text/field.dart';

class RegisterPage extends StatefulWidget {
  final Function()? onTap;
  const RegisterPage({super.key, required this.onTap});

  @override
  // ignore: library_private_types_in_public_api
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController userController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmpasswordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  bool isLoading = false;


  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.setLanguageCode('en');
  }

  @override
  void dispose() {
    nameController.dispose();
    userController.dispose();
    passwordController.dispose();
    confirmpasswordController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  // Sign Up method
  void userUp() async {
    try {
      if (passwordController.text == confirmpasswordController.text) {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: userController.text.trim(),
          password: passwordController.text.trim(),
        );

        if (!mounted) return;
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(userCredential.user!.uid)
            .set({
          'name': nameController.text.trim(),
          'email': userController.text.trim(),
          'phonenumber': phoneController.text.trim(),
        });

        if (!mounted) return;
        showSuccessMessage("Account created successfully!");

        Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const Navigate()),
          );
        }
});

      } else {
        showErrormessage("Passwords don't match!");
      }
    } on FirebaseAuthException catch (e) {
      showErrormessage(e.message ?? "An error occurred");
    } catch (e) {
      showErrormessage("Something went wrong. Please try again.");
    }
  }

  void showErrormessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.red,
          title: Center(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  void showSuccessMessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.green,
          title: Center(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
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

                // Sign up button
                Button(text: "Sign Up", onTap: userUp),

                const SizedBox(height: 20),

                // Login now
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Have an account?"),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: (){
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
