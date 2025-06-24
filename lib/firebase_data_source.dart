import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
class FirebaseDataSource {
  final FirebaseFirestore _firestore=FirebaseFirestore.instance;
  createSession() async{
    try{
      final createdSession=await _firestore.collection('rooms').add({
        'createdAt': FieldValue.serverTimestamp(),
      });
      return createdSession.id;
    } catch (e) {
      print('Error creating session: $e');
      return null;
    }
  }
  Future <String> addListener(String roomId) async{
    final listener= await _firestore.collection('rooms')
      .doc(roomId)
      .collection('participants').add({});
      return listener.id;
  }
  createHostId(String roomId) async {
    try {
      final hostSnapshot = await _firestore.collection('rooms').doc(roomId).collection('organizer').add({});
        return hostSnapshot.id;
    } catch (e) {
      print('Error getting host ID: $e');
    }
    return null;
  }
  getHostId(String roomId) async {
    try {
      final hostSnapshot = await _firestore.collection('rooms').doc(roomId).collection('organizer');
      final docs=await hostSnapshot.get();
      
        return docs.docs.first.id;
    } catch (e) {
      print('Error getting host ID: $e');
    }
    return null;
  }
  sendHostIceCandidates({required String roomId,required String hostId,required RTCIceCandidate candidate}) async{
    await _firestore.collection('rooms')
    .doc(roomId)
    .collection('organizer')
    .doc(hostId)
    .set({
      'candidates': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }
    });
  }
  pushOffer({required Map<String, dynamic> offer, required String roomId,required String hostId}) async {

    print("room Id is ======================>>>>>>>>>> $roomId");
    try {
      await _firestore.collection('rooms').doc(roomId).collection('organizer').doc(hostId).set({
        'offer': offer
      });
      
    } catch (e) {
      print('Error pushing offer: $e');
    }
  }
  getoffer(String roomId) async {
    try {
      final offerSnapshot = await _firestore.collection('rooms').doc(roomId).collection('organizer').get();
      if (offerSnapshot.docs.isNotEmpty) {
        return offerSnapshot.docs.first.data()['offer'];
      }
    } catch (e) {
      print('Error getting offer: $e');
    }
    return null;
  }
  sendListeneranswer({required String roomId, required Map<String,dynamic> answer,required String participantId}) async{
    try {
      final listenerId = await _firestore.collection('rooms')
      .doc(roomId)
      .collection('participants').doc(participantId)
      .set({
        'answer': answer,
      });
    } catch (e) {
      print('Error sending listener answer: $e');
    }
  }
  sendListenerIceCandidates({required String roomId, required String listenerId, required RTCIceCandidate candidate}) async {
    await _firestore.collection('rooms')
    .doc(roomId)
    .collection('participants')
    .doc(listenerId)
    .set({
      'candidates': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }
    });
  }
  Future<CollectionReference<Map<String, dynamic>>> onNewListener(String roomId) async {
    try {
      return _firestore.collection('rooms')
        .doc(roomId)
        .collection('participants');
    } catch (e) {
      throw Exception('Error getting new listener: $e');
    }
  }
  Future<CollectionReference<Map<String, dynamic>>> getListenerIceCandidates(String roomId, String listenerId) async {
    try {
      return _firestore.collection('rooms')
        .doc(roomId)
        .collection('participants')
        .doc(listenerId)
        .collection('candidates');
    } catch (e) {
      throw Exception('Error getting listener ICE candidates: $e');
    }
  }
  getListenerAnswer(String roomId, String listenerId) async {
    try {
      final answerSnapshot = await _firestore.collection('rooms')
        .doc(roomId)
        .collection('participants')
        .doc(listenerId)
        .snapshots();
        return answerSnapshot;
    } catch (e) {
      print('Error getting listener answer: $e');
    }
    return null;
  }
   Future<CollectionReference<Map<String, dynamic>>> getHostIceCandidates(String roomId, String hostId) async {
    try {
       return _firestore.collection('rooms')
        .doc(roomId)
        .collection('organizer')
        .doc(hostId)
        .collection('candidates');
    } catch (e) {
      throw Exception('Error getting host ICE candidates: $e');
    }
  }
}

  
