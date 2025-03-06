import 'package:flutter/material.dart';
import 'package:safe_pulse/onboarding/onboardingside.dart';
import 'package:safe_pulse/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class OnboardingDisplay extends StatefulWidget {
  const OnboardingDisplay({super.key});

  @override
  State<OnboardingDisplay> createState() => _OnboardingDisplayState();
}

class _OnboardingDisplayState extends State<OnboardingDisplay> {
  final controller = OnboardingSide();
  final pageController = PageController();

  bool isLastPage = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        bottomSheet: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: isLastPage ? startButton(context) :   Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              //skip button
              TextButton(
                  onPressed: () =>
                      pageController.jumpToPage(controller.items.length),
                  child: const Text("Skip")),

              Opacity(
                opacity: 0.0, // Hides the dots
                child: SmoothPageIndicator(
                  controller: pageController,
                  count: controller.items.length,
                  effect: const WormEffect(activeDotColor: Colors.blue),
                ),
              ),

              //next button
              TextButton(
                  onPressed: () => pageController.nextPage(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeIn),
                  child: const Text("Next")),
            ],
          ),
        ),
        body: Container(
          margin: const EdgeInsets.symmetric(horizontal: 15),
          child: PageView.builder(
            onPageChanged: (index)=> setState(()=> isLastPage =controller.items.length - 1 == index),
              itemCount: controller.items.length,
              controller: pageController,
              itemBuilder: (context, index) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(controller.items[index].image),
                    const SizedBox(height: 15),
                    Text(
                      controller.items[index].title,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      controller.items[index].description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    )
                  ],
                );
              }),
        ));
  }
}

//start button
Widget startButton(BuildContext context) {
  return Container(
    decoration:  const BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      color: Colors.blue,      
    ),
    width: MediaQuery.of(context).size.width * .9,
    height: 50,
    child: TextButton(
      onPressed: ()async{
        final prefs = await SharedPreferences.getInstance();
        prefs.setBool('onboarding', true);
        
        if (!context.mounted) return; 
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) =>  const LoginPage()));
      },
      child: const Text("Let's Sign in First",
      style: TextStyle(color: Colors.white),),
    ),
  );
}
