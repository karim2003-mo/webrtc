import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoRoom {
  String roomId;
  String organizerId; // Fixed typo: organaiserId -> organizerId
  String? participantId;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  FirebaseFirestore firestore;
  List<RTCVideoRenderer> renderers=[];
  
  VideoRoom({
    required this.firestore,
    required this.roomId,
    required this.organizerId, // Fixed typo
    this.participantId,
  }) {
    initialize();
  }
  
  Future<void> initialize() async {
    // Initialize the local video renderer
    await localRenderer.initialize();
    // Initialize the remote video renderer
    await remoteRenderer.initialize();
  }
  
  Future<Map<String, bool>> _checkMediaDevices() async { // Fixed method name
    // Check if the media devices are available
    final devices = await navigator.mediaDevices.enumerateDevices();
    bool hasCamera = false; // Fixed variable name
    bool hasMicrophone = false; // Fixed variable name
    
    for (var device in devices) {
      if (device.kind == 'videoinput') {
        hasCamera = true;
      } else if (device.kind == 'audioinput') {
        hasMicrophone = true;
      }
    }
    
    Map<String, bool> result = {
      'hasCamera': hasCamera,
      'hasMicrophone': hasMicrophone,
    };
    return result;
  }
  
  Future<AllRenders> startCall() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
      ]
    };
    
    final hasMediaDevices = await _checkMediaDevices(); // Fixed method call
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': hasMediaDevices['hasMicrophone'] ?? false,
      'video': hasMediaDevices['hasCamera'] ?? false,
    });
    
    peerConnection = await createPeerConnection(configuration);
    
    // Add connection listeners before adding tracks
    _addConnectionListeners(participantId!); // Fixed method name
    _handleIceCandidates();
    
    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });
    
    localRenderer.srcObject = localStream;
    
    await _createOffer();
    await _joinRoom(roomId);
    
    return AllRenders(localRenderer: localRenderer, remoteRenderers: renderers);
  }
  
  Future<void> _createOffer() async { // Added Future<void> return type
    if (peerConnection == null) {
      throw Exception('Peer connection is not initialized');
    }
    
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    
    // Create room document
    await firestore.collection('rooms').doc(roomId).set({
      'organizerId': organizerId, // Fixed typo
    });
    
    // Create participant document with offer
    await firestore
        .collection('rooms')
        .doc(roomId)
        .collection('participants')
        .doc(organizerId) // Fixed typo
        .set({ // Changed from update to set
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    });
    
    // Listen for answers from participants
    firestore
        .collection('rooms')
        .doc(roomId)
        .collection('participants')
        .snapshots()
        .listen((snapshot) async {
      for (var participant in snapshot.docs) {
        if (participant.id != organizerId && participant.data().containsKey('answer')) {
          final answer = participant.data()['answer'];
          try {
            await peerConnection!.setRemoteDescription(
                RTCSessionDescription(answer['sdp'], answer['type']));
          } catch (e) {
            print('Error setting remote description: $e');
          }
        }
      }
    });
  }
  
  Future<void> _joinRoom(String roomId) async { // Added Future<void> return type
    try {
      DocumentSnapshot roomSnapshot = await firestore.collection('rooms').doc(roomId).get();
      
      if (roomSnapshot.exists) {
        // Get the organizer's offer
        final organizerDoc = await roomSnapshot.reference
            .collection('participants')
            .doc(roomSnapshot['organizerId']) // Fixed reference
            .get();
        
        if (organizerDoc.exists && organizerDoc.data()!.containsKey('offer')) {
          final offer = organizerDoc.data()!['offer'];
          
          await peerConnection!.setRemoteDescription(
              RTCSessionDescription(offer['sdp'], offer['type']));
          
          RTCSessionDescription answer = await peerConnection!.createAnswer();
          await peerConnection!.setLocalDescription(answer);
          
          // Create participant document with answer
          await firestore
              .collection('rooms')
              .doc(roomId)
              .collection('participants')
              .doc(participantId!)
              .set({ // Changed from update to set
            'answer': {
              'sdp': answer.sdp,
              'type': answer.type,
            },
          });
        }
      }
    } catch (e) {
      print('Error joining room: $e');
    }
  }
  
  void _addConnectionListeners(String userId) { // Fixed method name
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) { // Fixed null check
        firestore
            .collection('rooms')
            .doc(roomId)
            .collection('participants')
            .doc(userId)
            .set({
          'candidates': FieldValue.arrayUnion([{ // Changed to array for multiple candidates
            'candidate': candidate.candidate,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'sdpMid': candidate.sdpMid,
          }])
        }, SetOptions(merge: true));
      }
    };
    
peerConnection?.onTrack = (RTCTrackEvent event) {
  if (event.streams.isNotEmpty) {
    remoteRenderer.srcObject = event.streams[0];
    renderers.add(remoteRenderer);
  }
};
    
    peerConnection?.onRemoveStream = (stream) {
      remoteRenderer.srcObject = null;
    };
    
    // Add ICE connection state listener
    peerConnection?.onIceConnectionState = (state) {
      print('ICE Connection State: $state');
    };
  }
  
  // Add method to handle incoming ICE candidates
  void _handleIceCandidates() {
    firestore
        .collection('rooms')
        .doc(roomId)
        .collection('participants')
        .snapshots()
        .listen((snapshot) async {
      for (var participant in snapshot.docs) {
        if (participant.id != organizerId &&participant.data().containsKey('candidates')) {
          final candidates = participant.data()['candidates'] as List<dynamic>;
          for (var candidateData in candidates) {
            try {
              final candidate = RTCIceCandidate(
                candidateData['candidate'],
                candidateData['sdpMid'],
                candidateData['sdpMLineIndex'],
              );
              await peerConnection!.addCandidate(candidate);
            } catch (e) {
              print('Error adding ICE candidate: $e');
            }
          }
        }
      }
    });
  }
  
  // Add cleanup method
  Future<void> dispose() async {
    await localStream?.dispose();
    await peerConnection?.dispose();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}

class AllRenders {
  RTCVideoRenderer localRenderer;
  List<RTCVideoRenderer> remoteRenderers;
  
  AllRenders({
    required this.localRenderer,
    required this.remoteRenderers,
  });
}