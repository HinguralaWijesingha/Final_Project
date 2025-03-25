import 'package:contacts_service/contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safe_pulse/text/dialog_box.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({Key? key}) : super(key: key);

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  List<Contact> contacts = [];
  @override
  void initState() {
    super.initState();
    askpermissions();
  }

  Future<void> askpermissions() async {
    PermissionStatus status = await getContactsPermission();
    if (status == PermissionStatus.granted) {
      getAllContacts();
    } else {
      InvaliedPermissions(status);
    }
  }

  InvaliedPermissions(PermissionStatus status) {
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
    List<Contact> _contacts = await ContactsService.getContacts();
    setState(() {
      contacts = _contacts;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:contacts.length==0?
      const Center(child: CircularProgressIndicator()):
      ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (BuildContext context, int index){
          Contact contact = contacts[index];
          return ListTile(
            title: Text(contact.displayName!,
          ),
          leading: contact.avatar!=null && contact.avatar!.length>0?
          CircleAvatar(
            backgroundImage: MemoryImage(contact.avatar!),
          ):CircleAvatar(
            child: Text(contact.initials()),
          )
          );
        }
        ),
    );
  }
}
