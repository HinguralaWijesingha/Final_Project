import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class PoliceStation extends StatelessWidget {
  final Function(String) onMapFunction;
  const PoliceStation({Key? key, required this.onMapFunction}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        children: [
          InkWell(
            onTap: (){
              onMapFunction('Police Stations near me');
            },
            child: Card(
              elevation: 3,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Container(
                height: 50,
                width: 50,
                child: Center(
                  child: Image.asset('assets/ps.png',
                    height: 32,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            "Police Station",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            )
            ),
      ],
      ),
    );
  }
}
