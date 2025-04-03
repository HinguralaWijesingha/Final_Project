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

  //all user data
  final usersCollection = FirebaseFirestore.instance.collection('Users');

  //edit
  Future<void> edit(String field) async {
    String newValue = "";
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          "Edit $field",
          style: const TextStyle(color: Colors.white),
          ),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration:  InputDecoration(
              hintText: "Enter new $field",
              hintStyle: const TextStyle(color: Colors.grey),
            ),
            onChanged: (value) {
              newValue = value;
            },
          ),
          actions: [

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel",
              style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(newValue),
              child: const Text("Save",
              style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        
      ),
    );

    //update
    if(newValue.trim().length > 0){
      await usersCollection.doc(currentUser.uid).update({field: newValue});
    }
  }

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
                  onPressed: () => edit("email"),
                ),
                ProfileText(
                  text: userData['phonenumber'],
                  subText: "Phone Number",
                  onPressed: () => edit("phone number"),
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
