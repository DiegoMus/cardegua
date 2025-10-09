import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://jpvtmqnfaeptedozvoxe.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpwdnRtcW5mYWVwdGVkb3p2b3hlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4OTg0MjgsImV4cCI6MjA3NTQ3NDQyOH0.KV2YIxcoCadWVcRhdXwKtHObCVXNPwJ-FedAmV4C3pg',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Demo Auth Supabase', home: AuthPage());
  }
}
