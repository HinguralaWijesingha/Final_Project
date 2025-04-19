import 'package:flutter/material.dart';

class Hospital extends StatelessWidget {
  final Function(String) onMapFunction;
  const Hospital({super.key, required this.onMapFunction});

  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        children: [
          InkWell(
            onTap: (){
              onMapFunction('Hospitals near me');
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
                  child: Image.asset('assets/ho.png',
                    height: 32,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            " Hospitals",
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
