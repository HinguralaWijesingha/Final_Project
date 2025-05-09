import 'package:flutter/material.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/pages/chat_page.dart';
import 'package:sqflite/sqflite.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  DB db = DB();
  List<Dcontacts>? contactList;
  int count = 0;

  void showList() {
    Future<Database> dbFuture = db.initializeDatabase();
    dbFuture.then((database) {
      Future<List<Dcontacts>> contactListFuture = db.getContacts();
      contactListFuture.then((value) {
        setState(() {
          contactList = value;
          count = value.length;
        });
      });
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      showList();
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: prefer_conditional_assignment
    if (contactList == null) {
      contactList = [];
    }
    return Scaffold(
      body: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              const Text(
                "Your Chat Contacts",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: count == 0
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:  [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 80,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 20),
                            Text(
                              "No emergency contacts added yet",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Add contacts to start chatting",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: count,
                        itemBuilder: (BuildContext context, int index) {
                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                radius: 25,
                                child: Text(
                                  contactList![index].name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              title: Text(
                                contactList![index].name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  "Tap to chat",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatPage(
                                      contactId: contactList![index].id,
                                    ),
                                  ),
                                ).then((_) {
                                  // Refresh the list when returning from chat page
                                  showList();
                                });
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}