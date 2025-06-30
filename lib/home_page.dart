import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'profile_page.dart';
import 'item_detail_page.dart';
import 'constants.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
import 'messages_page.dart';

class HomePage extends StatefulWidget {
  final String userRole;
  const HomePage({super.key, required this.userRole});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final String userRole;
  int _currentIndex = 0;
  int _unreadCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  StreamSubscription<QuerySnapshot>? _chatSubscription;
  StreamSubscription<QuerySnapshot>? _itemsSubscription;
  final Map<String, StreamSubscription<QuerySnapshot>>
      _chatMessageSubscriptions = {};

  @override
  void initState() {
    userRole = widget.userRole;
    super.initState();
    _setupUnreadListener();
    _setupItemListener();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    for (final sub in _chatMessageSubscriptions.values) {
      sub.cancel();
    }
    _chatMessageSubscriptions.clear();
    _itemsSubscription?.cancel();
    super.dispose();
  }

  void _setupUnreadListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _chatSubscription?.cancel();
    for (final sub in _chatMessageSubscriptions.values) {
      sub.cancel();
    }
    _chatMessageSubscriptions.clear();

    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((chatSnapshot) {
      int totalUnread = 0;
      final now = DateTime.now();
      final Map<String, int> chatUnreadCounts = {};

      if (chatSnapshot.docs.isEmpty) {
        setState(() {
          _unreadCount = 0;
        });
        return;
      }

      for (final chatDoc in chatSnapshot.docs) {
        final chatId = chatDoc.id;
        _chatMessageSubscriptions[chatId]?.cancel();
        _chatMessageSubscriptions[chatId] = chatDoc.reference
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(10)
            .snapshots()
            .listen((msgSnapshot) {
          int chatUnread = 0;
          for (final msgDoc in msgSnapshot.docs) {
            final msg = msgDoc.data();
            if (msg['senderId'] != user.uid) {
              final ts = msg['timestamp'];
              DateTime? msgTime;
              if (ts is Timestamp) {
                msgTime = ts.toDate();
              } else if (ts is String) {
                msgTime = DateTime.tryParse(ts);
              }
              if (msgTime != null && now.difference(msgTime).inDays < 2) {
                chatUnread += 1;
                _addNotification(
                  type: 'message',
                  title: 'New message',
                  content: msg['text'] ?? 'You have a new message.',
                  timestamp: msgTime,
                  chatId: chatId,
                  itemId: chatDoc['itemId'],
                );
              }
            }
          }
          chatUnreadCounts[chatId] = chatUnread;
          setState(() {
            _unreadCount = chatUnreadCounts.values.fold(0, (a, b) => a + b);
          });
        });
      }
    });
  }

  void _setupItemListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _itemsSubscription = FirebaseFirestore.instance
        .collection('items')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] is Timestamp
            ? data['timestamp'].toDate()
            : DateTime.tryParse(data['timestamp'] ?? '');
        final alreadyExists = _notifications
            .any((n) => n['type'] == 'item' && n['itemId'] == doc.id);
        if (!alreadyExists && data['owner'] != user.uid) {
          _addNotification(
            type: 'item',
            title: 'New item posted',
            content: data['name'] ?? 'A new item has been posted.',
            timestamp: timestamp ?? DateTime.now(),
            itemId: doc.id,
          );
        }
      }
    });
  }

  void _addNotification({
    required String type,
    required String title,
    required String content,
    required DateTime timestamp,
    String? chatId,
    String? itemId,
  }) {
    final notif = {
      'type': type,
      'title': title,
      'content': content,
      'timestamp': timestamp,
      'chatId': chatId,
      'itemId': itemId,
    };
    final same = _notifications.any((n) =>
        n['type'] == type &&
        n['chatId'] == chatId &&
        n['itemId'] == itemId &&
        n['content'] == content);
    if (!same) {
      setState(() {
        _notifications.insert(0, notif);
      });
    }
  }

  Future<void> _onNotificationTap(Map<String, dynamic> notif) async {
    if (notif['type'] == 'item' && notif['itemId'] != null) {
      final doc = await FirebaseFirestore.instance
          .collection('items')
          .doc(notif['itemId'])
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ItemDetailPage(
            imageUrl: data['image'] ?? '',
            name: data['name'] ?? 'Unknown Item',
            description: data['description'] ?? '',
            dateLost: data['date_lost'] ?? data['timestamp'],
            documentId: notif['itemId'],
            publicId: data['public_id'],
            userRole: userRole,
          ),
        ));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Item not found')));
      }
    } else if (notif['type'] == 'message' && notif['chatId'] != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MessagesPage(
          chatId: notif['chatId'],
          otherUserName: '', // Optionally fetch username
        ),
      ));
    }
  }

  void _showNotificationsPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400, // fixes size for desktop
              maxHeight: 500,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.98),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const Divider(),
                  Expanded(
                    child: _notifications.isEmpty
                        ? const Center(
                            child: Text(
                              'No notifications yet.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _notifications.length,
                            itemBuilder: (context, idx) {
                              final notif = _notifications[idx];
                              return ListTile(
                                leading: notif['type'] == 'item'
                                    ? const Icon(Icons.add_box,
                                        color: Colors.blue)
                                    : const Icon(Icons.message,
                                        color: Colors.green),
                                title: Text(notif['title'] ?? ''),
                                subtitle: Text(notif['content'] ?? ''),
                                trailing: Text(
                                  notif['timestamp'] is DateTime
                                      ? DateFormat('MMM d, h:mm a')
                                          .format(notif['timestamp'])
                                      : '',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black54),
                                ),
                                onTap: () async {
                                  Navigator.of(context).pop();
                                  await _onNotificationTap(notif);
                                },
                              );
                            },
                          ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _notifications.clear();
                      });
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear All',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 1) {
        setState(() {
          _unreadCount = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [
        ItemsPage(
          unreadCount: _unreadCount,
          notifications: _notifications,
          onNotificationBellTap: () => _showNotificationsPopup(context),
          userRole: userRole,
        ),
        const MessagesPage(),
        const ProfilePage(),
      ][_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFF0B2A92),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white60,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.message),
                if (_unreadCount > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class ItemsPage extends StatefulWidget {
  final int unreadCount;
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onNotificationBellTap;
  final String userRole;
  const ItemsPage({
    super.key,
    required this.unreadCount,
    required this.notifications,
    required this.onNotificationBellTap,
    required this.userRole,
  });

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isUploading = false;
  String _searchQuery = '';

  User? get currentUser => FirebaseAuth.instance.currentUser;

  Future<void> _pickImageAndUpload() async {
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        _nameController.clear();
        _descController.clear();

        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Add Item Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Item Name',
                      hintText: 'Enter item name (e.g., Wallet, Phone)',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Enter detailed description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Item name cannot be empty")),
                    );
                    return;
                  }
                  if (_descController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Description cannot be empty")),
                    );
                    return;
                  }
                  Navigator.of(context).pop();
                  await _uploadItem(
                    pickedFile,
                    _nameController.text.trim(),
                    _descController.text.trim(),
                  );
                  _nameController.clear();
                  _descController.clear();
                },
                child: const Text('Upload'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking image: $e")),
        );
      }
    }
  }

  Future<void> _uploadItem(
      XFile imageFile, String name, String description) async {
    if (!mounted) return;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in to add items")),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final imageUrl = await CloudinaryService.uploadImage(imageFile);

      // Optionally: Extract and save publicId if your upload returns it
      final publicId = null; // Set from Cloudinary response if needed

      await FirestoreService.addItemForUserAndFeed(
        uid: currentUser!.uid,
        imageUrl: imageUrl,
        name: name,
        description: description,
        publicId: publicId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Item uploaded successfully! 🎉"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteItem(String docId, String? publicId, bool isOwner) async {
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in to delete items")),
      );
      return;
    }
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You don't have permission to delete this item."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      await FirestoreService.deleteItemEverywhere(
        uid: currentUser!.uid,
        docId: docId,
      );
      if (publicId != null && publicId.isNotEmpty) {
        await CloudinaryService.deleteImage(publicId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Item deleted successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (e.toString().toLowerCase().contains('permission-denied')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You don't have right to delete this item."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error deleting item: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDate(dynamic timestamp) {
    return FirestoreService.formatDate(timestamp);
  }

  List<QueryDocumentSnapshot> _filterItems(List<QueryDocumentSnapshot> docs) {
    if (_searchQuery.isEmpty) return docs;

    return docs.where((doc) {
      final data = doc.data()! as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final description = (data['description'] ?? '').toString().toLowerCase();
      final searchLower = _searchQuery.toLowerCase();

      return name.contains(searchLower) || description.contains(searchLower);
    }).toList();
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }

  int _getCrossAxisCount(double width) {
    if (width >= 1100) return 4;
    if (width >= 700) return 3;
    if (width >= 450) return 2;
    return 1;
  }

  double _getMaxPageWidth(double width) {
    // Center the grid on large screens, full width on mobile
    if (width > 1300) return 1200;
    if (width > 900) return 900;
    return double.infinity;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = widget.unreadCount;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF0B2A92),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = _getCrossAxisCount(width);
                final maxPageWidth = _getMaxPageWidth(width);
                return Center(
                  child: Container(
                    width: maxPageWidth,
                    padding: EdgeInsets.all(width < 600 ? 8 : 32),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.image,
                                        color: Colors.white),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search items...',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: _clearSearch,
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: widget.onNotificationBellTap,
                              child: Stack(
                                children: [
                                  const Icon(Icons.notifications_none,
                                      color: Colors.white, size: 28),
                                  if (unreadCount > 0 ||
                                      widget.notifications.isNotEmpty)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Text(
                                          (unreadCount +
                                                      widget.notifications
                                                          .length) >
                                                  99
                                              ? '99+'
                                              : '${unreadCount + widget.notifications.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (_searchQuery.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search,
                                    color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Searching for: "$_searchQuery"',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _clearSearch,
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirestoreService.getItemsStream(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                );
                              }

                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Error: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }

                              final allDocs = snapshot.data?.docs ?? [];
                              final filteredDocs = _filterItems(allDocs);

                              if (allDocs.isEmpty) {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.photo_library_outlined,
                                          color: Colors.white70, size: 64),
                                      SizedBox(height: 16),
                                      Text(
                                        'Add your first item',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              if (filteredDocs.isEmpty &&
                                  _searchQuery.isNotEmpty) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.search_off,
                                          color: Colors.white70, size: 64),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No items found for "$_searchQuery"',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: _clearSearch,
                                        child: const Text(
                                          'Clear search',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: width < 600 ? 10 : 18,
                                  mainAxisSpacing: width < 600 ? 10 : 18,
                                  childAspectRatio: 0.75,
                                ),
                                itemCount: filteredDocs.length,
                                itemBuilder: (context, index) {
                                  final data = filteredDocs[index].data()!
                                      as Map<String, dynamic>;
                                  final isOwner = currentUser != null &&
                                      data['owner'] == currentUser!.uid;
                                  return GestureDetector(
                                    onTap: () async {
                                      final shouldDelete =
                                          await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ItemDetailPage(
                                            imageUrl: data['image'] ?? '',
                                            name:
                                                data['name'] ?? 'Unknown Item',
                                            description:
                                                data['description'] ?? '',
                                            dateLost: data['date_lost'] ??
                                                data['timestamp'],
                                            documentId: filteredDocs[index].id,
                                            publicId: data['public_id'],
                                            userRole: widget.userRole,
                                          ),
                                        ),
                                      );

                                      if (shouldDelete == true) {
                                        await _deleteItem(
                                          filteredDocs[index].id,
                                          data['public_id'],
                                          isOwner,
                                        );
                                      }
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(12),
                                                topRight: Radius.circular(12),
                                              ),
                                              child: Image.network(
                                                data['image'] ?? '',
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                loadingBuilder: (context, child,
                                                    loadingProgress) {
                                                  if (loadingProgress == null)
                                                    return child;
                                                  return Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                      color: Colors.white,
                                                      value: loadingProgress
                                                                  .expectedTotalBytes !=
                                                              null
                                                          ? loadingProgress
                                                                  .cumulativeBytesLoaded /
                                                              loadingProgress
                                                                  .expectedTotalBytes!
                                                          : null,
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Container(
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          const BorderRadius
                                                              .only(
                                                        topLeft:
                                                            Radius.circular(12),
                                                        topRight:
                                                            Radius.circular(12),
                                                      ),
                                                    ),
                                                    child: const Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(Icons.broken_image,
                                                            color:
                                                                Colors.white70,
                                                            size: 32),
                                                        Text('Failed to load',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white70)),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    data['name'] ??
                                                        'Unknown Item',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    data['description'] ??
                                                        'No description',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    _formatDate(
                                                        data['date_lost'] ??
                                                            data['timestamp']),
                                                    style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 10,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          floatingActionButton: widget.userRole == 'admin'
              ? FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: _isUploading ? null : _pickImageAndUpload,
                  tooltip: 'Add Post',
                  child: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0B2A92),
                          ),
                        )
                      : const Icon(Icons.add, color: Color(0xFF0B2A92)),
                )
              : null,
        ),
        if (_isUploading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Uploading image...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
