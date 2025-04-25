import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart';

import '../models/message.dart';
import '../models/profile.dart';
import '../utils/constants.dart';
import './splash_page.dart';

Future<void> logout() async {
  final channel = supabase.channel('presence');
  await channel.untrack(); // Stop tracking presence
  await channel.unsubscribe(); // Unsubscribe from the channel
  await Supabase.instance.client.auth.signOut();
}

/// Page to chat with someone.
///
/// Displays chat bubbles as a ListView and TextField to enter new chat.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.senderId});

  final String senderId; // Sender ID as a string (UUID)

  static Route<void> route({required String senderId}) {
    return MaterialPageRoute(
      builder: (context) => ChatPage(senderId: senderId),
    );
  }

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final Stream<List<Message>> _messagesStream;

  final Map<String, Profile> _profileCache = {};


  late final Stream<bool> _senderStatusStream;
  StreamController<bool>? _statusStreamController;
  Timer? _statusCheckTimer;


  @override
  void initState() {
    final myUserId = supabase.auth.currentUser!.id;
    print("myUserId...$myUserId");
    print("senderId...${widget.senderId}");

    // Assuming the user ID is a numeric string and converting it to an integer
    final myUserIdInt = int.tryParse(myUserId) ?? 0; // Default to 0 if parsing fails

    _messagesStream = Message.watchMessages(myUserId);


    _statusStreamController = StreamController<bool>.broadcast();
    _senderStatusStream = _statusStreamController!.stream;
    _startStatusCheck();


    // Initialize the sender's presence stream
    // _senderStatusStream = _watchSenderStatus(myUserIdInt);
    //
    // // Track the current user's presence
    // _trackUserPresence(myUserIdInt);

    super.initState();
  }


  void _startStatusCheck() {
    // Check immediately
    _checkAndEmitStatus();
    // Then start periodic checking
    _statusCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _checkAndEmitStatus();
    });
  }

  Future<void> _checkAndEmitStatus() async {
    final online = await _isOnline();
    _statusStreamController?.add(online);
  }


  Future<bool> _isOnline() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    // Check if any result indicates an active network
    return connectivityResults.any((result) =>
    result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet ||
        result == ConnectivityResult.vpn);
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _statusStreamController?.close();
    supabase.channel('presence').unsubscribe();
    super.dispose();
  }


  void _trackUserPresence(int userId) {
    final channel = supabase.channel('presence');
    channel.subscribe((status, [error]) {
      if (status == 'SUBSCRIBED') {
        channel.track({'user_id': userId});
      }
    });
  }

  Stream<bool> _watchSenderStatus(int senderId) {
    final channel = supabase.channel('presence');
    final streamController = StreamController<bool>.broadcast();
    channel.onPresenceSync((payload) {
      final presenceState = channel.presenceState();
      final isOnline = presenceState[senderId] != null;
      streamController.add(isOnline);
    }).subscribe();
    streamController.onCancel = () {
      channel.unsubscribe();
      streamController.close();
    };
    return streamController.stream.distinct(); // Only emit unique updates
  }


  Future<void> _loadProfileCache(String profileId) async {
    if (_profileCache[profileId] != null) {
      return;
    }
    final profile = await Profile.findProfileById(profileId);
    setState(() {
      _profileCache[profileId] = profile;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<bool>(
          stream: _senderStatusStream,
          builder: (context, snapshot) {
            String statusText;
            Color statusColor;
            if (snapshot.connectionState == ConnectionState.waiting) {
              statusText = 'Loading...';
              statusColor = Colors.grey;
            } else {
              final isOnline = snapshot.data ?? false;
              statusText = isOnline ? 'Online' : 'Offline';
              statusColor = isOnline ? Colors.green : Colors.red;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chat'),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: StreamBuilder<List<Message>>(
        stream: _messagesStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final messages = snapshot.data!;
            return Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                    child: Text('Start your conversation now :)'),
                  )
                      : ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];

                      /// I know it's not good to include code that is not related
                      /// to rendering the widget inside build method, but for
                      /// creating an app quick and dirty, it's fine 😂
                      _loadProfileCache(message.profileId);

                      return _ChatBubble(
                        message: message,
                        profile: _profileCache[message.profileId],
                      );
                    },
                  ),
                ),
                const _MessageBar(),
              ],
            );
          } else {
            return preloader;
          }
        },
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(''),
            ),
            ListTile(
              title: const Text('Sign Out'),
              onTap: () async {
                var navigator = Navigator.of(context);
                navigator.pop();
                await logout();
                navigator.pushReplacement(MaterialPageRoute(
                  builder: (context) => const SplashPage(),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  // @override
  // void dispose() {
  //   // Unsubscribe from the presence channel to avoid memory leaks
  //   supabase.channel('presence').unsubscribe();
  //   super.dispose();
  // }
}

/// Set of widget that contains TextField and Button to submit message
class _MessageBar extends StatefulWidget {
  const _MessageBar();

  @override
  State<_MessageBar> createState() => _MessageBarState();
}

class _MessageBarState extends State<_MessageBar> {
  late final TextEditingController _textController;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[200],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  keyboardType: TextInputType.text,
                  maxLines: null,
                  autofocus: true,
                  controller: _textController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message',
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _submitMessage(),
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    _textController = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<bool> _isOnline() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    // Check if any result indicates an active network
    return connectivityResults.any((result) =>
    result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet ||
        result == ConnectivityResult.vpn);
  }


  void _submitMessage() async {
    final text = _textController.text;
    final myUserId = supabase.auth.currentUser!.id;
    if (text.isEmpty) {
      return;
    }
    _textController.clear();

    final isOnline = await _isOnline();
    print("isOnline...$isOnline");
    final status = isOnline ? MessageStatus.sent : MessageStatus.pending;


    // Create message with appropriate status
    await Message.create(myUserId, text, status);

    //await Message.create(myUserId, text);
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.profile,
  });

  final Message message;
  final Profile? profile;


  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment:
        isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            CircleAvatar(
              radius: 16,
              child: profile == null
                  ? preloader
                  : Text(profile!.username.substring(0, 2)),
            ),
          if (!isMine) const SizedBox(width: 8),

          /// Bubble
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMine
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft:
                  isMine ? const Radius.circular(12) : Radius.zero,
                  bottomRight:
                  isMine ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isMine ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        format(message.createdAt, locale: 'en_short'),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMine ? Colors.white70 : Colors.black45,
                        ),
                      ),
                      if (isMine) const SizedBox(width: 4),
                      if (isMine)
                        Icon(
                          message.status == MessageStatus.pending
                              ? Icons.access_time // Clock icon for pending
                              : message.status == MessageStatus.sent
                              ? Icons.check // Single check
                              : Icons.done_all, // Delivered
                          size: 14,
                          color: message.status == MessageStatus.delivered
                              ? Colors.white
                              : Colors.white70,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 8),
        ],
      ),
    );
  }


  //
  // @override
  // Widget build(BuildContext context) {
  //   List<Widget> chatContents = [
  //     if (!message.isMine)
  //       CircleAvatar(
  //         child: profile == null
  //             ? preloader
  //             : Text(profile!.username.substring(0, 2)),
  //       ),
  //     const SizedBox(width: 12),
  //     Flexible(
  //       child: Container(
  //         padding: const EdgeInsets.symmetric(
  //           vertical: 8,
  //           horizontal: 12,
  //         ),
  //         decoration: BoxDecoration(
  //           color: message.isMine
  //               ? Theme.of(context).primaryColor
  //               : Colors.grey[300],
  //           borderRadius: BorderRadius.circular(8),
  //         ),
  //         child: Text(message.content),
  //       ),
  //     ),
  //     const SizedBox(width: 12),
  //     Text(format(message.createdAt, locale: 'en_short')),
  //     //Text(message.createdAt.toString()),
  //     const SizedBox(width: 60),
  //
  //     if (message.isMine)
  //       Icon(
  //         message.status == MessageStatus.pending
  //             ? Icons.access_time // Clock icon for pending
  //             : message.status == MessageStatus.sent
  //             ? Icons.check // Single check for sent
  //             : Icons.done_all, // Double check for delivered
  //         size: 16,
  //         color: message.status == MessageStatus.delivered
  //             ? Colors.green // Green for delivered
  //             : Colors.grey, // Grey for pending and sent
  //       ),
  //
  //   ];
  //   if (message.isMine) {
  //     chatContents = chatContents.reversed.toList();
  //   }
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
  //     child: Row(
  //       mainAxisAlignment:
  //       message.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
  //       children: chatContents,
  //     ),
  //   );
  // }
}