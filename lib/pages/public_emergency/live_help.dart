import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/widgets/live/police_station.dart';

class LiveHelp extends StatelessWidget {
  const LiveHelp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      width: MediaQuery.of(context).size.width,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        children: const [
          PoliceStation(),
        ],
      ),
    );
  }
}
