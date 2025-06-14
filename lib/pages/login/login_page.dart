import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/login/forget_password_page.dart';
import 'package:safe_pulse/text/button.dart';

class LoginPage extends StatefulWidget {
  final Function()? onTap;
  const LoginPage({super.key, required this.onTap});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controllers
  final TextEditingController userController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
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

  // Sign in method
  void userIn() async {
    setState(() {
      isLoading = true;
    });
    
    // loading circle
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );
    
    try {
      // sign in
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: userController.text.trim(),
        password: passwordController.text.trim()
      );
      
      // pop the loading circle
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);

        Navigator.pushReplacementNamed(context, '/navigate');

      }

      
    } on FirebaseAuthException catch (e) {
      // pop the loading circle
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // Show appropriate error message
      if (e.code == 'user-not-found') {
        showErrormessage("No user found with this email");
      } else if (e.code == 'wrong-password') {
        wrongPasswordMessage();
      } else {
        showErrormessage("Error: ${e.message}");
      }
    } catch (e) {
      // pop the loading circle
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      showErrormessage("An error occurred. Please try again.");
    } finally {
      setState(() {
        isLoading = false;
      });
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
                const SizedBox(height: 10),

                // App logo
                Image.asset(
                  'assets/lo23.png',
                  width: 100,
                  height: 100,
                ),

                const SizedBox(height: 20),

                Text(
                  "Your safety is our priority.".toUpperCase(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),

                const SizedBox(height: 25),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: TextField(
                    controller: userController,
                    obscureText: false,
                    decoration: InputDecoration(
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: "Enter Your Email",
                      fillColor: Colors.grey[200],
                      filled: true,
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: "Enter Your Password",
                      fillColor: Colors.grey[200],
                      filled: true,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) {
                                return const ForgetPasswordPage();
                              },
                            ),
                          );
                        },
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Sign in button
                Button(
                  text: isLoading ? "Signing In..." : "Sign In", 
                  onTap: isLoading ? null : userIn
                ),

                const SizedBox(height: 30),

                // Sign in method divider
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(color: Colors.black),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text("Or create an account"),
                      ),
                      Expanded(
                        child: Divider(color: Colors.black),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Register now
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Not a member?"),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        widget.onTap?.call();
                      },
                      child: const Text(
                        "Register Now",
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