import 'package:safe_pulse/onboarding/onboardinginfo.dart';

class OnboardingSide {
   List<OnboardingInfo> items = [
      OnboardingInfo(
         title: "Welcome to Safe Pulse! 🚀",
         description: "Your safety matters! Get real-time alerts, GPS tracking, and quick emergency access. Stay protected with SOS, fake calls, and offline support. 🚀🔒",
         image: "assets/p2.png"
      ),

        OnboardingInfo(
         title: "Stay Safe, Stay Connected! 🚨",
         description: "Trigger an SOS with a tap, shake, or power press. Share your location instantly for quick help! 🚨📍",
         image: "assets/p3.png"
      ),
      
        OnboardingInfo(
         title: "Enable Permissions for Safety",
         description: "To ensure your safety, please enable location, SMS, and notification permissions. These allow real-time tracking, emergency alerts, and quick communication during emergencies. Stay protected with seamless support! 🚨📍",
         image: "assets/p1.png"
      )

   ];
}
