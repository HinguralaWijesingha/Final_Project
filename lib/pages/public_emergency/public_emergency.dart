import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/widgets/public_contact/ambulance.dart';
import 'package:safe_pulse/pages/widgets/public_contact/fire.dart';
import 'package:safe_pulse/pages/widgets/public_contact/police_emergency.dart';
import 'package:safe_pulse/pages/widgets/public_contact/woman.dart';

class PublicEmergencyContacts extends StatelessWidget {
  const PublicEmergencyContacts({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: 180,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        children: const [
          PoliceContact(),
          Ambulance(),
          WomanMinistry(),
          FireStation(),
        ],
      ),
    );
  }
}
