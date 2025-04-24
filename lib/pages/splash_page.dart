// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import './chat_page.dart';
import './register_page.dart';
import '../utils/constants.dart';

/// Page to redirect users to the appropriate page depending on the initial auth state
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  SplashPageState createState() => SplashPageState();
}

class SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    // await for for the widget to mount
    await Future.delayed(Duration.zero);

    final session = supabase.auth.currentSession;
    if (session == null) {
      Navigator.of(context)
          .pushAndRemoveUntil(RegisterPage.route(), (route) => false);
    } else {
      final userId = supabase.auth.currentUser!.id; // Get the current user's ID
      Navigator.of(context).pushAndRemoveUntil(
        ChatPage.route(senderId: userId), // Pass the user's ID as senderId
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: preloader);
  }
}
