import 'package:connectivity_plus/connectivity_plus.dart'; // Add this for network status
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';

import 'app_config_template.dart';
import 'models/schema.dart';

final log = Logger('powersync-supabase');

/// Postgres Response codes that we cannot recover from by retrying.
final List<RegExp> fatalResponseCodes = [
  RegExp(r'^22...$'),
  RegExp(r'^23...$'),
  RegExp(r'^42501$'),
];

late final PowerSyncDatabase db;

Future<String> getDatabasePath() async {
  const dbFilename = 'powersync-demo.db';
  if (kIsWeb) {
    return dbFilename;
  }
  final dir = await getApplicationSupportDirectory();
  return join(dir.path, dbFilename);
}

bool isLoggedIn() {
  return Supabase.instance.client.auth.currentSession?.accessToken != null;
}

/// Check if the device is online
Future<bool> isOnline() async {
  final connectivityResult = await Connectivity().checkConnectivity();
  return connectivityResult != ConnectivityResult.none;
}

Future<void> openDatabase() async {
  db = PowerSyncDatabase(schema: schema, path: await getDatabasePath());
  await db.initialize();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  SupabaseConnector? currentConnector;

  if (isLoggedIn()) {
    currentConnector = SupabaseConnector();
    db.connect(connector: currentConnector);
  }

  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    final AuthChangeEvent event = data.event;
    if (event == AuthChangeEvent.signedIn) {
      currentConnector = SupabaseConnector();
      db.connect(connector: currentConnector!);
    } else if (event == AuthChangeEvent.signedOut) {
      currentConnector = null;
      await db.disconnect();
    } else if (event == AuthChangeEvent.tokenRefreshed) {
      currentConnector?.prefetchCredentials();
    }
  });
}

class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector();

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    log.info('uploading data...');
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    final rest = Supabase.instance.client.rest;
    final isDeviceOnline = await isOnline();

    try {
      for (var op in transaction.crud) {
        final table = rest.from(op.table);

        // Set initial status based on network connectivity
        var initialStatus = isDeviceOnline ? 'sent' : 'pending';

        print("initialStatus...$initialStatus");

        if (op.op == UpdateType.put) {
          var data = Map<String, dynamic>.of(op.opData!);
          data['id'] = op.id;
          data['status'] = initialStatus; // Set initial status
          await table.upsert(data);

          // Update status to 'sent' if online
          if (op.table == 'messages' && isDeviceOnline) {
            await rest.from('messages').update({
              'status': 'sent', // One tick
            }).eq('id', op.id);
          }

        } else if (op.op == UpdateType.patch) {
          var data = Map<String, dynamic>.of(op.opData!);
          data['status'] = initialStatus; // Set initial status
          await table.update(data).eq('id', op.id);

          // Update status to 'sent' if online
          if (op.table == 'messages' && isDeviceOnline) {
            await rest.from('messages').update({
              'status': 'sent', // One tick
            }).eq('id', op.id);
          }

        } else if (op.op == UpdateType.delete) {
          await table.delete().eq('id', op.id);
        }
      }

      await transaction.complete();

      // Update status to 'delivered' for messages if online
      if (isDeviceOnline) {
        for (var op in transaction.crud) {
          if (op.table == 'messages' && op.op != UpdateType.delete) {
            await rest.from('messages').update({
              'status': 'delivered', // Two ticks
            }).eq('id', op.id);
          }
        }
      }

    } on PostgrestException catch (e) {
      print("exception...$e");
      // Revert to 'pending' status for messages on failure
      for (var op in transaction.crud) {
        if (op.table == 'messages' && op.op != UpdateType.delete) {
          await rest.from('messages').update({
            'status': 'pending', // Mark as pending on failure
          }).eq('id', op.id);
        }
      }
      if (e.code != null && fatalResponseCodes.any((re) => re.hasMatch(e.code!))) {
        await transaction.complete();
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return null;
    }

    final token = session.accessToken;

    return PowerSyncCredentials(endpoint: AppConfig.powersyncUrl, token: token);
  }
}