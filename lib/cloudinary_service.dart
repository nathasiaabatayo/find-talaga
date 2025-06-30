import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'constants.dart';

class CloudinaryService {
  static Future<String> uploadImage(XFile imageFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(kCloudinaryApiUrl));
      request.fields['upload_preset'] = kCloudinaryUploadPreset;

      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          filename: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
      }

      var response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        final imageUrl = responseData['secure_url'];
        final publicId = responseData['public_id'];

        if (imageUrl == null) throw Exception('Image URL not found');
        return imageUrl;
      } else {
        throw Exception(
            'Upload failed (Status: ${response.statusCode})\n$responseBody');
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> deleteImage(String publicId) async {
    try {
      final response = await http.post(
        Uri.parse(kCloudinaryDeleteUrl),
        body: {
          'public_id': publicId,
          'api_key': '919111354139559',
          'timestamp':
              (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
          'signature': 'your_signature',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete from Cloudinary: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error deleting from Cloudinary: $e');
      rethrow;
    }
  }
}
