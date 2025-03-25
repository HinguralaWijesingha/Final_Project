import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ForgetPasswordPage extends StatefulWidget {
  const ForgetPasswordPage({Key? key}) : super(key: key);

  @override
State<ForgetPasswordPage> createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<ForgetPasswordPage> {

  final userController = TextEditingController();

  @override
  void dispose() {
    userController.dispose();
    super.dispose();
  }

  Future ResetPassword() async {
    try{
      await FirebaseAuth.instance.sendPasswordResetEmail(email: userController.text.trim());
      showDialog(
        context: context,
        builder: (context) {
          return const AlertDialog(
            content: Text('Password reset link send to your email'),
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      print(e);
      showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: Text(e.message.toString()),
            );
          });
    }
    }


  @override
  Widget build(BuildContext context) {
    return  Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text("Forget Password"),
      ),
      body:Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children:[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25.0),
            child:  Text("Enter Your Email to send the reset password link",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20),
            ),
          ),

          const SizedBox(height: 15),

          //forget password feild
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: TextField(
              controller: userController,
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

          const SizedBox(height: 10),

          //forget password button
          MaterialButton(
            onPressed: ResetPassword,
            height: 45,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textColor: Colors.white,
            color: Colors.green,
            child: const Text("Reset Password"),
          )
        ],
      ),
    );
  }
}