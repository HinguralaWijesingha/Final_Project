import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/pages/contact_page.dart';
import 'package:safe_pulse/text/button.dart';
import 'package:sqflite/sqflite.dart';

class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage> {
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

  void deleteContact(Dcontacts contact) async {
    int result = await db.deleteContact(contact.id);
    if (result != 0) {
      Fluttertoast.showToast(msg: "Contact Deleted Successfully");
      showList();
    }
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
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const SizedBox(
                height: 20,
              ),
              Button(
                  onTap: () async {
                    bool result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ContactPage()));
                    if (result == true) {
                      showList();
                    }
                  },
                  text: "Add Emergency Contact"),
              Expanded(
                child: ListView.builder(
                  //shrinkWrap: true,
                  itemCount: count,
                  itemBuilder: (BuildContext context, int index) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ListTile(
                          title: Text(contactList![index].name),
                          trailing: SizedBox(
                            width: 100,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.call),
                                  color: Colors.red,
                                  onPressed: () async {
                                    await FlutterPhoneDirectCaller.callNumber(
                                        contactList![index].number);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  color: Colors.red,
                                  onPressed: () {
                                    deleteContact(contactList![index]);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
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
