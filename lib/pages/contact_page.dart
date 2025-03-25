import 'package:contacts_service/contacts_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/text/dialog_box.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({Key? key}) : super(key: key);

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  List<Contact> contacts = [];
  List<Contact> contactsFilter = [];
  DB _db = DB();

  TextEditingController searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    askpermissions();
  }

  String pattenPhoneNumber(String phone) {
    return phone.replaceAllMapped(RegExp(r'^(\+)|\D'), (Match m) {
      return m[0] == "+" ? "+" : "";
    });
  }

  cleanContact() {
    List<Contact> _contacts = [];
    _contacts.addAll(contacts);
    if (searchController.text.isNotEmpty) {
      _contacts.retainWhere((element) {
        String searchTerm = searchController.text.toLowerCase();
        String contactNumber = pattenPhoneNumber(searchTerm);
        String contactName = element.displayName!.toLowerCase();
        bool matchName = contactName.contains(searchTerm);
        if (matchName == true) {
          return true;
        }
        if (contactNumber.isEmpty) {
          return false;
        }
        var contactPhone = element.phones!.firstWhere((p) {
          String phnpatten = pattenPhoneNumber(p.value!);
          return phnpatten.contains(contactNumber);
        });
        return contactPhone.value != null;
      });
    }
    setState(() {
      contactsFilter = _contacts;
    });
  }

  Future<void> askpermissions() async {
    PermissionStatus status = await getContactsPermission();
    if (status == PermissionStatus.granted) {
      getAllContacts();
      searchController.addListener(() {
        cleanContact();
      });
    } else {
      invaliedPermissions(status);
    }
  }

  invaliedPermissions(PermissionStatus status) {
    if (status == PermissionStatus.denied) {
      dialogueBox(context, "Access to contacts is denied by user");
    } else if (status == PermissionStatus.permanentlyDenied) {
      dialogueBox(context, "Contacts doesn't exit in this device");
    }
  }

  Future<PermissionStatus> getContactsPermission() async {
    PermissionStatus permission = await Permission.contacts.status;
    if (permission != PermissionStatus.granted &&
        permission != PermissionStatus.permanentlyDenied) {
      PermissionStatus status = await Permission.contacts.request();
      return status;
    } else {
      return permission;
    }
  }

  getAllContacts() async {
    List<Contact> _contacts =
        await ContactsService.getContacts(withThumbnails: false);
    setState(() {
      contacts = _contacts;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isSearchIng = searchController.text.isNotEmpty;
    bool listItemExit = (contactsFilter.length > 0 || contacts.length > 0);
    return Scaffold(
      body: contacts.length == 0
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      autofocus: false,
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: "Search Contact",
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  listItemExit == true
                      ? Expanded(
                          child: ListView.builder(
                            itemCount: isSearchIng == true
                                ? contactsFilter.length
                                : contacts.length,
                            itemBuilder: (BuildContext context, int index) {
                              Contact contact = isSearchIng == true
                                  ? contactsFilter[index]
                                  : contacts[index];
                              return ListTile(
                                title: Text(
                                  contact.displayName!,
                                ),
                                leading: contact.avatar != null &&
                                        contact.avatar!.length > 0
                                    ? CircleAvatar(
                                        backgroundImage:
                                            MemoryImage(contact.avatar!),
                                      )
                                    : CircleAvatar(
                                        child: Text(contact.initials()),
                                      ),
                                onTap: () {
                                  if (contact.phones!.isNotEmpty) {
                                    final String phoneNum =
                                        contact.phones!.first.value!;
                                    final String name = contact.displayName!;
                                    _addContact(Dcontacts( name, phoneNum));
                                  }else{
                                    Fluttertoast.showToast(msg: "Oops!! Contact has no phone number");
                                  }
                                },
                              );
                            },
                          ),
                        )
                      : Container(
                          child: const Text("search for contact"),
                        ),
                ],
              ),
            ),
    );
  }

  void _addContact(Dcontacts newContact) async {
    int result = await _db.insertContact(newContact);
    if (result != 0) {
       Fluttertoast.showToast(msg: "Contact Added Successfully");
    }else {
      Fluttertoast.showToast(msg: "Contact Not Added");
    }
    Navigator.of(context).pop(true);
  }
}
