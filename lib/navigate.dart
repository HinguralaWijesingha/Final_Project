import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

class Navigate extends StatefulWidget {
  const Navigate({super.key});

  @override
  State<Navigate> createState() => _NavigateState();
}

class _NavigateState extends State<Navigate> {
  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut(); // Sign out user
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        //title: const Text("Home"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.blue,
        child: const  Padding(
          padding:  EdgeInsets.symmetric(horizontal: 15, vertical: 20),
          child: GNav(
            gap: 8,
            backgroundColor: Colors.blue,
            color: Colors.black,
            activeColor: Colors.white,
            //tabBackgroundColor: Colors.red,
            padding:  EdgeInsets.all(9),
            tabs:  [
              GButton(
                icon: Icons.home,
                text: 'Home',
              ),
              GButton(
                icon: Icons.map,
                text: 'Map',
              ),
              GButton(
                icon: Icons.add,
                text: 'Add contact',
              ),
              GButton(
                icon: Icons.person,
                text: 'Profile',
              ),
              
            ],
            ),
        ),
      ),
    );
  }
}
