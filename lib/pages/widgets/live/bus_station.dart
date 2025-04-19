import 'package:flutter/material.dart';

class BusStation extends StatelessWidget {
  final Function(String) onMapFunction;
  const BusStation({super.key, required this.onMapFunction});

  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        children: [
          InkWell(
            onTap: (){
              onMapFunction('Bus Stations near me');
            },
            child: Card(
              elevation: 3,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: SizedBox(
                height: 50,
                width: 50,
                child: Center(
                  child: Image.asset('assets/bc.png',
                    height: 32,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            " Bus Stations",
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
