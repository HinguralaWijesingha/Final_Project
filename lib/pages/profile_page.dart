import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:safe_pulse/pages/widgets/profile_text.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final currentUser = FirebaseAuth.instance.currentUser!;

  //edit
  Future<void> edit(String field) async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          //get users data
          if (snapshot.hasData) {
            final userData = snapshot.data!.data() as Map<String, dynamic>?;
            return ListView(
              children: [
                const SizedBox(
                  height: 40,
                ),
                const Icon(
                  Icons.person,
                  size: 70,
                  color: Colors.black,
                ),
                const SizedBox(
                  height: 10,
                ),
                Text(
                  currentUser.email!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black),
                ),
                const SizedBox(
                  height: 30,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 25.0),
                  child: Text('My Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      )),
                ),
                ProfileText(
                  text: userData!['name'],
                  subText: "User Name",
                  onPressed: () => edit("name"),
                ),
                ProfileText(
                  text: currentUser.email!,
                  subText: "Email",
                  onPressed: () => edit("name"),
                ),
                ProfileText(
                  text: userData['phonenumber'],
                  subText: "Phone Number",
                  onPressed: () => edit("name"),
                ),
              ],
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error${snapshot.error}'),
            );
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
      // },
    );
  }
}
