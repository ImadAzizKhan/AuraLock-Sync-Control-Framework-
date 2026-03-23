import 'package:cloud_firestore/cloud_firestore.dart';


class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // ==== NEW: SUB-STATION PROFILE (TOTAL POINTS) ====
  // Yeh stream Boss app ko aapke live points degi
  Stream<DocumentSnapshot> getSubStationProfile() {
    return _db.collection('users').doc('sub_station').snapshots();
  }

  // Pehli dafa profile banane ke liye (Ya reset karne ke liye)
  Future<void> initSubStationProfile() async {
    var doc = await _db.collection('users').doc('sub_station').get();
    if (!doc.exists) {
      await _db.collection('users').doc('sub_station').set({
        'rewardPoints': 0,
        'punishmentPoints': 0,
      });
    }
  }

  

  // 1. Task Save Karna
  Future<void> createTask(String title, int points, String frequency, String time, bool requiresProof) async {
    await _db.collection('tasks').add({
      'title': title,
      'points': points,
      'frequency': frequency,
      'time': time,
      'requiresProof': requiresProof,
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });
  }

  // 2. Reward Save Karna
  Future<void> createReward(String title, int price) async {
    await _db.collection('rewards').add({
      'title': title,
      'price': price,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 3. Rule Save Karna
  Future<void> createRule(String description) async {
    await _db.collection('rules').add({
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ==== UPDATED: Penalties WITH POINTS & PROOF ====
  Future<void> createPunishment(String reason, int requiredPunishmentPoints, bool requiresProof) async {
    await _db.collection('Penalties').add({
      'reason': reason,
      'requiredPoints': requiredPunishmentPoints, // Puranay 'penalty' ki jagah
      'requiresProof': requiresProof, // Naya addition
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  
}