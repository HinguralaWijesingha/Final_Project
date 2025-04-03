import 'package:flutter/material.dart';

class ProfileText extends StatelessWidget {
  final String text;
  final String subText;
  final void Function() onPressed;
  const ProfileText({super.key, required this.text, required this.subText, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.only(
        left: 15,
        bottom: 15,
      ),
      margin: const EdgeInsets.only(left: 20, right: 20, top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                subText,
                style:   TextStyle(
                  color: Colors.grey[500],
                ),
              ),

              IconButton(
                onPressed: onPressed, 
                icon: const Icon(
                  Icons.edit,
                  size: 16,
                  ),
              ),


            ],
          ),
          Text(
            text
          ),
        ],
      ),
    );
  }
}
