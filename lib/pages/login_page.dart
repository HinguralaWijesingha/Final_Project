import 'package:flutter/material.dart';
import 'package:safe_pulse/text/button.dart';
import 'package:safe_pulse/text/field.dart';
import 'package:safe_pulse/text/image.dart';

class LoginPage extends StatelessWidget {
   LoginPage({super.key});


  //controllers
  final usercontroller = TextEditingController();
  final passwordcontroller = TextEditingController();


  //sign in
  void userIn(){}

  @override
  Widget build(BuildContext context) {
    return  Scaffold(
      backgroundColor: Colors.grey[300],
      body:  SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 50),


            //app name
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
              "Welcome back you've been missed",
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
              )
            ),

            const SizedBox(height: 25),

             Field(
              controller: usercontroller,
              obscureText: false,
              hintText: "Username",
            ),
            

              const SizedBox(height: 15),

             Field(
              controller: passwordcontroller,
              obscureText: true,
              hintText: "Password",
            ),


            //forget password

             const SizedBox(height: 10),

             const Padding(
              padding:  EdgeInsets.symmetric(horizontal: 25.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "Forgot Password?",
                    style: TextStyle(
                      color: Colors.blue,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold
                      ), 
                  ),
                ],
              ),
            ),


            const SizedBox(height: 25),


            //sign in button
             Button(
              onTap: userIn,
           ),



            const SizedBox(height: 30),

           //sign in method

           Padding(
             padding: const EdgeInsets.symmetric(horizontal: 25.0),
             child: Row(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 20, right: 20),
                    color: Colors.black,
                    height: 1,
                  ),
                ),
                
                const Padding(
                  padding:  EdgeInsets.symmetric(horizontal: 10.0),
                  child:  Text("Or continue with"),
                ),
             
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 20, right: 20),
                    color: Colors.black,
                    height: 1,
                  ),
                ),  
              ],
             ),
           ),


            const SizedBox(height: 50),

           const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ImageText(imagePath: 'assets/google.png'),

              SizedBox(width: 20),

              ImageText(imagePath: 'assets/apple.png'),
            ],
           ),


            const SizedBox(height: 30),

           //register now
           const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Text(
                "Not a member?"
                ),
               SizedBox(width: 4),
               Text(
                "Register now",
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold
                  ),
                )
            ],  
           )

              

















          ],
        ),
      ),
    )
    );
  }
}