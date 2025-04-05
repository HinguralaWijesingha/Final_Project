import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:safe_pulse/pages/widgets/live/hospital.dart';
import 'package:safe_pulse/pages/widgets/live/police_station.dart';
import 'package:url_launcher/url_launcher.dart';

class LiveHelp extends StatelessWidget {
  const LiveHelp({Key? key}) : super(key: key);

  static Future<void> openMap(String location) async {
    String googleUrl ='https://www.google.com/maps/search/$location';
    final Uri _url = Uri.parse(googleUrl);
    try {
      await launchUrl(_url);
    } catch (e) {
      Fluttertoast.showToast(msg: "Error");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      width: MediaQuery.of(context).size.width,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        children: const [
          PoliceStation(onMapFunction: openMap,),
          SizedBox(width: 24,),
          Hospital(onMapFunction: openMap,),
        ],
      ),
    );
  }
}
