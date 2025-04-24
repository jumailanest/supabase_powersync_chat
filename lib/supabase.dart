import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config_template.dart';



loadSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
}
