import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';

class MessagesPage extends StatelessWidget {
  final String? chatId;
  final String? otherUserName;

  const MessagesPage({Key? key, this.chatId, this.otherUserName})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (chatId != null && otherUserName != null) {
      return ChatScreen(chatId: chatId!, otherUserName: otherUserName!);
    } else {
      return const ChatListScreen();
    }
  }
}

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B2A92),
        body: Center(
          child: Text("You must be logged in to see messages",
              style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B2A92),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B2A92),
        title: const Text('Messages', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Center(
            child: Container(
              width: isWide ? 600 : double.infinity,
              padding: isWide
                  ? const EdgeInsets.symmetric(vertical: 20)
                  : EdgeInsets.zero,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirestoreService.getUserChatsStream(currentUser.uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  final chats = snapshot.data!.docs;
                  if (chats.isEmpty) {
                    return const Center(
                      child: Text(
                        "No conversations yet.",
                        style: TextStyle(color: Colors.white70, fontSize: 18),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => Divider(
                      color: Colors.white24,
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      final participants =
                          List<String>.from(chat['participants']);
                      final chatId = chat.id;
                      final currentUid = currentUser.uid;
                      final otherUid = participants.firstWhere(
                          (uid) => uid != currentUid,
                          orElse: () => currentUid);

                      // Fetch both user and item info for chat tile
                      return FutureBuilder<List<dynamic>>(
                        future: Future.wait([
                          FirebaseFirestore.instance
                              .collection('users')
                              .doc(otherUid)
                              .get(),
                          (chat['itemId'] != null &&
                                  chat['itemId'].toString().isNotEmpty)
                              ? FirebaseFirestore.instance
                                  .collection('items')
                                  .doc(chat['itemId'])
                                  .get()
                              : Future.value(null),
                        ]),
                        builder: (context, userItemSnap) {
                          String title = "Chat";
                          String itemName = chat['itemName'] ?? '';
                          String? itemImageUrl;
                          if (userItemSnap.hasData && userItemSnap.data != null) {
                            final userSnap = userItemSnap.data![0] as DocumentSnapshot?;
                            final itemSnap = userItemSnap.data![1] as DocumentSnapshot?;
                            if (userSnap != null && userSnap.exists) {
                              final userData = userSnap.data() as Map<String, dynamic>;
                              // Prefer firstName + lastName if available
                              final firstName = userData['firstName'] ?? '';
                              final lastName = userData['lastName'] ?? '';
                              if (firstName.isNotEmpty || lastName.isNotEmpty) {
                                title = (firstName + ' ' + lastName).trim();
                              } else {
                                title = userData['username'] ?? "Chat with $otherUid";
                              }
                            }
                            if (itemSnap != null && itemSnap.exists) {
                              final data = itemSnap.data() as Map<String, dynamic>;
                              itemName = data['name'] ?? itemName;
                              itemImageUrl = data['image'];
                            }
                          }
                          return ListTile(
                            leading: itemImageUrl != null
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(itemImageUrl),
                                    backgroundColor: Colors.white24,
                                  )
                                : const CircleAvatar(
                                    backgroundColor: Colors.white24,
                                    child:
                                        Icon(Icons.chat, color: Colors.white),
                                  ),
                            title: Text(
                              title,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (itemName.isNotEmpty)
                                  Text(
                                    itemName,
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                const Text(
                                  "Contact",
                                  style: TextStyle(
                                      color: Colors.lightBlueAccent,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MessagesPage(
                                    chatId: chatId,
                                    otherUserName: title,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;

  const ChatScreen(
      {Key? key, required this.chatId, required this.otherUserName})
      : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final User? currentUser = FirebaseAuth.instance.currentUser;

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || currentUser == null) return;
    await FirestoreService.sendMessage(
      chatId: widget.chatId,
      senderId: currentUser!.uid,
      text: text,
    );
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B2A92),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B2A92),
        title: Text(
          widget.otherUserName,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Center(
            child: Container(
              width: isWide ? 600 : double.infinity,
              child: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirestoreService.getMessagesStream(widget.chatId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error: ${snapshot.error}',
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 16),
                            ),
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No messages yet!',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 18),
                            ),
                          );
                        }
                        final messages = snapshot.data!.docs;
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 12),
                          reverse: true,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final data = messages[messages.length - 1 - index]
                                .data() as Map<String, dynamic>;
                            final isMe = data['senderId'] == currentUser?.uid;
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.white : Colors.white24,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  data['text'] ?? '',
                                  style: TextStyle(
                                    color: isMe
                                        ? const Color(0xFF0B2A92)
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send,
                                color: Color(0xFF0B2A92)),
                            onPressed: _sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
