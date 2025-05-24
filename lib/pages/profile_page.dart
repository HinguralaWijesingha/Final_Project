import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/login/login_page.dart';
import 'package:safe_pulse/pages/widgets/profile_text.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  final usersCollection = FirebaseFirestore.instance.collection('Users');
  bool isDeleting = false;

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
          decoration: InputDecoration(
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
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(newValue),
            child: const Text(
              "Save",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (newValue.trim().isNotEmpty) {
      await usersCollection.doc(currentUser.uid).update({field: newValue});
    }
  }

  Future<void> _deleteUserAccount() async {
    setState(() => isDeleting = true);
    
    try {
      // First delete Firestore data
      await _deleteUserData();
      
      // Then delete auth account
      await _deleteAuthAccount();
      
      // Navigate to login page
      _navigateToLogin();
      
    } catch (e) {
      _showErrorSnackbar(e);
    } finally {
      setState(() => isDeleting = false);
    }
  }

  Future<void> _deleteUserData() async {
    try {
      await usersCollection.doc(currentUser.uid).delete();
      

    } catch (e) {
      debugPrint('Error deleting user data: $e');
      rethrow;
    }
  }

  Future<void> _deleteAuthAccount() async {
    try {
      await currentUser.delete();
    } catch (e) {
      debugPrint('Error deleting auth account: $e');
      rethrow;
    }
  }

  void _navigateToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) =>  LoginPage(onTap: () {  },)),
      (Route<dynamic> route) => false,
    );
  }

  void _showErrorSnackbar(dynamic error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to delete account: ${error.toString()}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete all your data. This action cannot be undone.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete Forever',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteUserAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot>(
        stream: usersCollection.doc(currentUser.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('User data not found'));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;

          return Stack(
            children: [
              ListView(
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.person, size: 70, color: Colors.black),
                  const SizedBox(height: 10),
                  Text(
                    currentUser.email!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.only(left: 25.0),
                    child: Text(
                      'My Details',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ProfileText(
                    text: userData['name'],
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
                    onPressed: () => edit("phonenumber"),
                  ),
                  const SizedBox(height: 50),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: isDeleting ? null : () => _confirmDeleteAccount(context),
                      child: isDeleting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Delete My Account',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
              if (isDeleting)
                const ModalBarrier(
                  color: Colors.black54,
                  dismissible: false,
                ),
            ],
          );
        },
      ),
    );
  }
}