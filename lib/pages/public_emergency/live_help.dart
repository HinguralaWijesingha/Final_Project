import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safe_pulse/pages/widgets/live/bus_station.dart';
import 'package:safe_pulse/pages/widgets/live/fire_station.dart';
import 'package:safe_pulse/pages/widgets/live/hospital.dart';
import 'package:safe_pulse/pages/widgets/live/police_station.dart';
import 'package:url_launcher/url_launcher.dart';

class LiveHelp extends StatelessWidget {
  const LiveHelp({Key? key}) : super(key: key);

  static Future<void> openMap(String placeType) async {
    try {
      // location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Fluttertoast.showToast(msg: "Location services are disabled.");
        return;
      }

      //  permission checking
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Fluttertoast.showToast(msg: "Location permission denied.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Fluttertoast.showToast(msg: "Location permission permanently denied.");
        return;
      }

      //  Get current location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latitude = position.latitude;
      final longitude = position.longitude;

      //   Google Maps query with current location
      final query = "$placeType near $latitude,$longitude";
      final Uri googleMapUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$query',
      );

      // Step 5: Launch Maps
      if (!await launchUrl(googleMapUrl, mode: LaunchMode.externalApplication)) {
        Fluttertoast.showToast(msg: "Could not open map.");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Error fetching location.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //  Police Station , Fire Station
              Column(
                children:  [
                  PoliceStation(onMapFunction: openMap),
                  SizedBox(height: 20),
                  FireStations(onMapFunction: openMap),
                ],
              ),
              SizedBox(width: 40),
              //Hospital, Bus Station
              Column(
                children: [
                  Hospital(onMapFunction: openMap),
                  SizedBox(height: 20),
                  BusStation(onMapFunction: openMap),
                ],
              ),
              
            ],
          ),
        ],
      ),
    );
  }
}
