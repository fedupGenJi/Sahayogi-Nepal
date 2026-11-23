import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';


enum AppLanguage { english, nepali }

class AppLanguageController {
  static const _key = 'app_language';
  static final ValueNotifier<AppLanguage> language =
      ValueNotifier(AppLanguage.english);

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    language.value = preferences.getString(_key) == 'ne'
        ? AppLanguage.nepali
        : AppLanguage.english;
  }

  static Future<void> toggle() async {
    language.value = language.value == AppLanguage.english
        ? AppLanguage.nepali
        : AppLanguage.english;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      language.value == AppLanguage.nepali ? 'ne' : 'en',
    );
  }
}

/// English source strings double as keys so untranslated screens retain their
/// original copy while the public request flow is translated incrementally.
String appText(String english) =>
    (AppLanguageController.language.value == AppLanguage.nepali
        ? _nepali[english]
        : null) ??
    english;

class AppLanguageToggle extends StatelessWidget {
  const AppLanguageToggle({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: AppLanguageController.toggle,
        style: TextButton.styleFrom(
          minimumSize: const Size(56, 42),
          foregroundColor: appTeal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        child: Text(
          AppLanguageController.language.value == AppLanguage.english
              ? 'नेपाली'
              : 'EN',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );

const _nepali = <String, String>{
  'Request Help': 'सहयोग माग्नुहोस्',
  'Donate resources': 'स्रोतसाधन दान गर्नुहोस्',
  'Request assistance': 'सहायता माग्नुहोस्',
  'Change language': 'भाषा परिवर्तन गर्नुहोस्',
  'You’re not alone.\nLet’s find you support.': 'तपाईं एक्लै हुनुहुन्न।\nसहयोग खोजौँ।',
  'Request\nAssistance': 'सहायता\nमाग्नुहोस्',
  'Donate\nResources': 'स्रोतसाधन\nदान गर्नुहोस्',
  'Become a\nVolunteer': 'स्वयंसेवक\nबन्नुहोस्',
  'Home': 'गृहपृष्ठ',
  'Explore': 'अन्वेषण',
  'Requests': 'अनुरोधहरू',
  'Join': 'सामेल हुनुहोस्',
  'Tell us what you need.': 'तपाईंलाई के चाहिन्छ बताउनुहोस्।',
  'What can you share?': 'तपाईं के दिन सक्नुहुन्छ?',
  'Where is help needed?': 'कहाँ सहायता चाहिन्छ?',
  'Contact information': 'सम्पर्क जानकारी',
  'Contact number': 'सम्पर्क नम्बर',
  'Assistance type': 'सहायताको प्रकार',
  'Number of volunteers needed': 'आवश्यक स्वयंसेवक संख्या',
  'What kind of human\nassistance do you need?': 'कस्तो मानवीय\nसहायता चाहिन्छ?',
  'Requester name': 'अनुरोधकर्ताको नाम',
  'Donor name': 'दाता नाम',
  'Resource category': 'स्रोतको प्रकार',
  'Required quantity': 'आवश्यक परिमाण',
  'Required Number': 'आवश्यक संख्या',
  'Available quantity': 'उपलब्ध परिमाण',
  'Estimated number of affected people': 'प्रभावित व्यक्तिको अनुमानित संख्या',
  'Pickup location': 'उठाउने स्थान',
  'Choose location': 'स्थान छान्नुहोस्',
  'Change location': 'स्थान परिवर्तन गर्नुहोस्',
  'Choose location on map': 'नक्सामा स्थान छान्नुहोस्',
  'e.g. 8 people': 'जस्तै: ८ जना',
  'e.g. 8': 'जस्तै: ८',
  'Add another assistance type': 'अर्को सहायता प्रकार थप्नुहोस्',
  'Food · Drinking Water · Medicine\nClothing · Temporary Shelter': 'खाना · पिउने पानी · औषधि\nलुगा · अस्थायी आश्रय',
  'Pickup selected:': 'उठाउने स्थान छानियो:',
  'Choose a resource category.': 'स्रोतको प्रकार छान्नुहोस्।',
  'Choose an assistance type.': 'सहायताको प्रकार छान्नुहोस्।',
  'Enter a valid quantity': 'मान्य परिमाण लेख्नुहोस्',
  'Enter a valid number of affected people': 'प्रभावित व्यक्तिको मान्य संख्या लेख्नुहोस्',
  'Choose a pickup location.': 'सामान उठाउने स्थान छान्नुहोस्।',
  'Add another resource': 'अर्को स्रोत थप्नुहोस्',
  'Select a category': 'प्रकार छान्नुहोस्',
  'Select category': 'प्रकार छान्नुहोस्',
  'Enter a number': 'संख्या लेख्नुहोस्',
  'Your full name': 'तपाईंको पूरा नाम',
  'Phone number for responders to reach you': 'सम्पर्कका लागि फोन नम्बर',
  'Submit request': 'अनुरोध पठाउनुहोस्',
  'Share resources': 'स्रोतसाधन उपलब्ध गराउनुहोस्',
  'Submitting…': 'पठाउँदै…',
  'Food': 'खाना',
  'Food supplies': 'खाद्यान्न',
  'Drinking Water': 'पिउने पानी',
  'Drinking water': 'पिउने पानी',
  'Medicine': 'औषधि',
  'Clothing': 'लुगा',
  'Temporary Shelter': 'अस्थायी आश्रय',
  'Temporary shelter': 'अस्थायी आश्रय',
  'AI fill form': 'AI बाट फाराम भर्नुहोस्',
  'Describe what you need in English, नेपाली, or both.': 'आफूलाई चाहिएको कुरा English, नेपाली वा दुवै भाषामा लेख्नुहोस्।',
  'Describe what you can donate in English, नेपाली, or both.': 'तपाईंले दिन सक्ने कुरा English, नेपाली वा दुवै भाषामा लेख्नुहोस्।',
  'Describe the assistance needed in English, नेपाली, or both.': 'आवश्यक सहायता English, नेपाली वा दुवै भाषामा लेख्नुहोस्।',
  'Review suggestions': 'सुझाव जाँच्नुहोस्',
  'Apply to form': 'फाराममा राख्नुहोस्',
  'AI suggestions are ready to review.': 'AI का सुझाव जाँच्न तयार छन्।',
  'requester_name': 'अनुरोधकर्ताको नाम',
  'requester_phone': 'सम्पर्क नम्बर',
  'affected_people': 'प्रभावित व्यक्तिहरू',
  'assistance_type': 'सहायताको प्रकार',
  'volunteers_needed': 'स्वयंसेवक संख्या',
  'items': 'सामग्रीहरू',
  'Cancel': 'रद्द गर्नुहोस्',
  'Health Worker': 'स्वास्थ्यकर्मी',
  'Transport Manpower': 'यातायात जनशक्ति',
  'Human Manpower': 'मानवीय जनशक्ति',
  'English': 'अङ्ग्रेजी',
  'नेपाली': 'नेपाली',
};
