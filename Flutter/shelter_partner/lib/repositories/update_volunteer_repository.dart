import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdateVolunteerRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Method to modify a specific string attribute within the volunteer document
  Future<void> modifyVolunteerLastActivity(
      String volunteerId, Timestamp newValue) async {
    final docRef = _firestore.collection('users').doc(volunteerId);
    return docRef.update({
      'lastActivity': newValue,
    }).catchError((error) {
      throw Exception("Failed to modify: $error");
    });
  }
}

// Provider for AddNoteRepository
final updateVolunteerRepositoryProvider = Provider<UpdateVolunteerRepository>((ref) {
  return UpdateVolunteerRepository();
});
