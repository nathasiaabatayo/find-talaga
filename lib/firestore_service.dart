import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class FirestoreService {
  // ======== ITEMS =========

  /// GLOBAL FEED
  static Stream<QuerySnapshot> getItemsStream() {
    return FirebaseFirestore.instance
        .collection('items')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// USER'S OWN ITEMS
  static Stream<QuerySnapshot<Map<String, dynamic>>> getUserItemsStream(
      String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('items')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Add item to both global and user collection
  static Future<void> addItemForUserAndFeed({
    required String uid,
    required String imageUrl,
    required String name,
    required String description,
    String? publicId,
  }) async {
    final itemData = {
      'image': imageUrl,
      'name': name,
      'description': description,
      'owner': uid,
      'timestamp': FieldValue.serverTimestamp(),
      'date_lost': DateTime.now().toIso8601String(),
      if (publicId != null) 'public_id': publicId,
    };

    // Add to global feed, get docId
    final docRef =
        await FirebaseFirestore.instance.collection('items').add(itemData);

    // Add to user's personal collection (with same doc id)
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('items')
        .doc(docRef.id)
        .set(itemData);
  }

  /// Delete item from both global and user collection
  static Future<void> deleteItemEverywhere({
    required String uid,
    required String docId,
  }) async {
    // Delete from global
    await FirebaseFirestore.instance.collection('items').doc(docId).delete();
    // Delete from user subcollection
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('items')
        .doc(docId)
        .delete();
  }

  static String formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is String) {
      try {
        dateTime = DateTime.parse(timestamp);
      } catch (e) {
        return 'Invalid date';
      }
    } else {
      return 'Unknown date';
    }

    return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
  }

  // ======== USERS =========
  static Future<void> addUserProfile({
    required String uid,
    required String username,
    required String lastname,
    required String email,
    String? phone,
    String? university,
    String? address,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'username': username,
      'lastname': lastname,
      'email': email,
      'phone': phone ?? '',
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserProfileStream(
      String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data();
  }

  // ======== CHATS =========

  static Future<String> createOrGetChat({
    required String itemId,
    required String itemName,
    required List<String> participantIds,
  }) async {
    // Try to find an existing chat for this item and these participants
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .where('itemId', isEqualTo: itemId)
        .get();

    for (var doc in snapshot.docs) {
      final participants = List<String>.from(doc['participants'] ?? []);
      if (participants.length == participantIds.length &&
          participants.toSet().containsAll(participantIds)) {
        return doc.id;
      }
    }

    // If not found, create a new chat
    final chatDoc = await FirebaseFirestore.instance.collection('chats').add({
      'itemId': itemId,
      'itemName': itemName,
      'participants': participantIds,
      'created_at': FieldValue.serverTimestamp(),
    });
    return chatDoc.id;
  }

  /// Send a chat message (add to messages subcollection)
  static Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Stream of messages for a chat
  static Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  /// Get all chats for a user (by uid)
  static Stream<QuerySnapshot> getUserChatsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('created_at', descending: true)
        .snapshots();
  }
}
