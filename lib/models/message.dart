import '../powersync.dart';
import 'package:powersync/sqlite3_common.dart' as sqlite;

enum MessageStatus {
  pending,
  sent,
  delivered
}

class Message {
  Message({
    required this.id,
    required this.profileId,
    required this.content,
    required this.createdAt,
    required this.isMine,
    required this.status,
  });

  final String id;
  final String profileId;
  final String content;
  final DateTime createdAt;
  final bool isMine;
  final MessageStatus status;

  // Modified constructor
  Message.fromMap(this.status, {
    required Map<String, dynamic> map,
    required String myUserId,
  })  : id = map['id'],
        profileId = map['profile_id'],
        content = map['content'],
        createdAt = DateTime.parse(map['created_at']),
        isMine = myUserId == map['profile_id'];

  // Modified factory to handle MessageStatus
  factory Message.fromRow(sqlite.Row row, String myUserId) {
    final statusString = row['status']; // Assuming status is stored as a string in the database
    final status = MessageStatus.values.firstWhere(
          (e) => e.toString() == 'MessageStatus.$statusString',
      orElse: () => MessageStatus.pending, // Default to sent if status is invalid
    );
    return Message(
      id: row['id'],
      profileId: row['profile_id'],
      content: row['content'],
      createdAt: DateTime.parse(row['created_at']),
      isMine: myUserId == row['profile_id'],
      status: status,
    );
  }

  static Stream<List<Message>> watchMessages(String myUserId) {
    return db
        .watch('SELECT * FROM messages ORDER BY created_at DESC')
        .map((results) {
      return results
          .map((row) => Message.fromRow(row, myUserId))
          .toList(growable: false);
    });
  }

  static Future<void> create(String profileId, String content,MessageStatus status,) async {
    await db.execute(
        'INSERT INTO messages(id, created_at, profile_id, content, status) VALUES(uuid(), datetime(), ?, ?, ?)',
        [profileId, content, status.toString().split('.').last]); // Set default status to 'sent'
  }

  // A method to update the message status (delivered)
  static Future<void> updateStatus(String messageId, MessageStatus status) async {
    await db.execute(
        'UPDATE messages SET status = ? WHERE id = ?',
        [status.toString().split('.').last, messageId]);
  }
}
