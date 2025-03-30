import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:safe_pulse/pages/public_emergency/public_emergency.dart';


class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("Public Emergency Contacts",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20
                ),),
              ),
             PublicEmergencyContacts(),
            ]
          ) ,
          ) ,
        ),
    );
  }
}