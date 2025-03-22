import 'package:flutter/material.dart';


class Field extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;

  const Field({
    super.key,
    required this.controller,
    required this.hintText,
    required this.obscureText,
    
    });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          enabledBorder:  OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(12),
          ),
          fillColor: Colors.grey[200],
          filled: true,
          hintText: hintText,
          
        ),
      ),
    );
  }
}
