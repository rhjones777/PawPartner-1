// volunteer_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelter_partner/models/volunteer.dart';




class VolunteerDetailsRepository {
  Future<Map<String, dynamic>> fetchLogsAndComputeStats(Volunteer volunteer) async {
    try {
      // Get the shelterID from the volunteer model
      String shelterID = volunteer.shelterID;

      // Initialize accumulators
      int totalLogDurationInMinutes = 0;
      int logCount = 0;

      // References to cats and dogs collections
      CollectionReference catsRef = FirebaseFirestore.instance
          .collection('shelters')
          .doc(shelterID)
          .collection('cats');

      CollectionReference dogsRef = FirebaseFirestore.instance
          .collection('shelters')
          .doc(shelterID)
          .collection('dogs');

      // Fetch all cats and dogs
      QuerySnapshot catsSnapshot = await catsRef.get();
      QuerySnapshot dogsSnapshot = await dogsRef.get();

      // Combine the snapshots
      List<QueryDocumentSnapshot> animalDocs = [
        ...catsSnapshot.docs,
        ...dogsSnapshot.docs
      ];

      // Iterate over each animal document
      for (var doc in animalDocs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // Extract logs
        List<dynamic> logsData = data['logs'] ?? [];

        for (var logData in logsData) {
          // Check if the log's authorID matches the volunteer's id
          if (logData['authorID'] == volunteer.id) {
            // Parse startTime and endTime
            Timestamp? startTimestamp = logData['startTime'];
            Timestamp? endTimestamp = logData['endTime'];

            if (startTimestamp != null && endTimestamp != null) {
              DateTime startTime = startTimestamp.toDate();
              DateTime endTime = endTimestamp.toDate();

              // Calculate the duration in minutes
              int durationInMinutes =
                  endTime.difference(startTime).inMinutes.abs();

              totalLogDurationInMinutes += durationInMinutes;
              logCount += 1;
            }
          }
        }
      }

      // Compute average log duration
      double averageLogDuration = logCount > 0
          ? totalLogDurationInMinutes / logCount.toDouble()
          : 0.0;

      // Return the computed values
      return {
        'totalTimeLoggedWithAnimals': totalLogDurationInMinutes,
        'averageLogDuration': averageLogDuration
      };
    } catch (e) {
      // Handle errors
      print('Error fetching logs: $e');
      throw e;
    }
  }
}


final volunteerRepositoryProvider = Provider<VolunteerDetailsRepository>((ref) {
  return VolunteerDetailsRepository();
});