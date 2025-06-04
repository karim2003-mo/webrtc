import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final bool isCaller;

  const VideoCallScreen({super.key, required this.roomId, required this.isCaller});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _screenStream;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startCall();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    // ignore: unnecessary_null_comparison
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };
  
    
      try{
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': true,
    });
        }
        catch (e) {
          print('Error accessing media devices: $e');
        }
    _peerConnection = await createPeerConnection(config);
    _peerConnection!.addStream(_localStream!);
    _localRenderer.srcObject = _localStream;

    _peerConnection!.onAddStream = (stream) {
      _remoteRenderer.srcObject = stream;
    };

    final roomRef = _firestore.collection('rooms').doc(widget.roomId);

    // Collect ICE candidates
    final callerCandidatesCollection = roomRef.collection('callerCandidates');
    final calleeCandidatesCollection = roomRef.collection('calleeCandidates');

    _peerConnection!.onIceCandidate = (candidate) async {
      final json = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };

      if (widget.isCaller) {
        await callerCandidatesCollection.add(json);
      } else {
        await calleeCandidatesCollection.add(json);
      }
    };

    if (widget.isCaller) {
      // Create Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await roomRef.set({'offer': offer.toMap()});

      // Listen for answer
      roomRef.snapshots().listen((snapshot) async {
        if (snapshot.data() != null && snapshot.data()!.containsKey('answer')) {
          final answer = RTCSessionDescription(
            snapshot.data()!['answer']['sdp'],
            snapshot.data()!['answer']['type'],
          );
          await _peerConnection!.setRemoteDescription(answer);
        }
      });

      // Listen for callee ICE candidates
      calleeCandidatesCollection.snapshots().listen((snapshot) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      });
    } else {
      // Join as callee
      final snapshot = await roomRef.get();
      if (snapshot.exists && snapshot.data()!.containsKey('offer')) {
        final offer = snapshot.data()!['offer'];
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']),
        );

        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        await roomRef.update({'answer': answer.toMap()});

        // Listen for caller ICE candidates
        callerCandidatesCollection.snapshots().listen((snapshot) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            _peerConnection!.addCandidate(RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ));
          }
        });

        // Listen for new callee ICE candidates
        calleeCandidatesCollection.snapshots().listen((snapshot) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            _peerConnection!.addCandidate(RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ));
          }
        });
      }
    }
  }
  sharescreen() async{
       final Map<String, dynamic> constraints = {
      'video': {
        // Preferred constraints (not mandatory)
        'width': {'ideal': MediaQuery.of(context).size.width},
        'height': {'ideal': MediaQuery.of(context).size.height},
        'frameRate': {'ideal': 30},
      },
      'audio': false,
    };
          _screenStream = await navigator.mediaDevices.getDisplayMedia(
            constraints
);
    if (_localStream != null) {
      _screenStream = await _localStream!.clone();
      _peerConnection!.addStream(_screenStream!);
      _remoteRenderer.srcObject = _screenStream;
      setState(() async{
              _localStream = _screenStream;
      _localRenderer.srcObject = _localStream;
      await _peerConnection?.addStream(_localStream!);
      });
    } else {
      print('No local stream available to share.');
    }
    
  }
  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _localStream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Call')),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
                Expanded(child: RTCVideoView(_remoteRenderer)),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    sharescreen();
                  },
                  child: const Text('Share Screen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
