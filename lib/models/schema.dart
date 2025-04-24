import 'package:powersync/powersync.dart';

const schema = Schema([
  Table('messages', [
    Column.text('profile_id'),
    Column.text('content'),
    Column.text('created_at'),
    Column.text('status'), // <-- Add this line
  ]),
  Table('profiles', [
    Column.text('username'),
    Column.text('created_at'),
  ]),
]);
