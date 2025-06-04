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
  bool _isSharingScreen = false;
  bool _hasCameraError = false;
  bool _hasMicError = false;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initRenderers().then((_) => _startCall());
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ]
      };

      _peerConnection = await createPeerConnection(config);

      // Try to get media with video first
      try {
        _localStream = await _getUserMedia(withVideo: true);
        _localRenderer.srcObject = _localStream;
        _peerConnection!.addStream(_localStream!);
      } catch (e) {
        print('Video error: $e');
        // Try without video if video fails
        _localStream = await _getUserMedia(withVideo: false);
        _localRenderer.srcObject = _localStream;
        _peerConnection!.addStream(_localStream!);
        setState(() => _hasCameraError = true);
      }

      _setupPeerConnectionListeners();
      
      if (widget.isCaller) {
        await _createOffer();
      } else {
        await _listenForOffer();
      }
    } catch (e) {
      print('Call setup error: $e');
      _showErrorDialog('Failed to start call: ${e.toString()}');
    }
  }

  Future<MediaStream> _getUserMedia({bool withVideo = true}) async {
    try {
      final media = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': withVideo ? {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'facingMode': 'user'
        } : false,
      });
      return media;
    } catch (e) {
      if (e.toString().contains('audio')) {
        setState(() => _hasMicError = true);
      }
      rethrow;
    }
  }

  void _setupPeerConnectionListeners() {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final callerCandidates = roomRef.collection('callerCandidates');
    final calleeCandidates = roomRef.collection('calleeCandidates');

    _peerConnection!.onIceCandidate = (candidate) async {
      final json = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };

      await (widget.isCaller ? callerCandidates : calleeCandidates).add(json);
    };

    _peerConnection!.onAddStream = (stream) {
      _remoteRenderer.srcObject = stream;
    };
  }

  Future<void> _createOffer() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    // Listen for answer
    roomRef.snapshots().listen((snapshot) async {
      if (snapshot.data()?.containsKey('answer') ?? false) {
        final answer = snapshot.data()!['answer'];
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
      }
    });

    // Listen for callee ICE candidates
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      _processCandidates(snapshot.docs);
    });
  }

  Future<void> _listenForOffer() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
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
      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        _processCandidates(snapshot.docs);
      });
    }
  }

  void _processCandidates(List<DocumentSnapshot> docs) {
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      _peerConnection!.addCandidate(RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      ));
    }
  }

  Future<void> toggleScreenSharing() async {
    try {
      if (_isSharingScreen) {
        await _stopScreenSharing();
      } else {
        await _startScreenSharing();
      }
    } catch (e) {
      _showErrorDialog('Screen sharing error: ${e.toString()}');
    }
  }

  Future<void> _startScreenSharing() async {
    final constraints = {
      'video': {
        'width': {'ideal': MediaQuery.of(context).size.width},
        'height': {'ideal': MediaQuery.of(context).size.height},
        'frameRate': {'ideal': 30},
      },
      'audio': false,
    };

    _screenStream = await navigator.mediaDevices.getDisplayMedia(constraints);
    _peerConnection?.removeStream(_localStream!);
    _peerConnection?.addStream(_screenStream!);
    _localRenderer.srcObject = _screenStream;

    _screenStream?.getVideoTracks().first.onEnded = () {
      if (mounted) toggleScreenSharing();
    };

    setState(() => _isSharingScreen = true);
  }

  Future<void> _stopScreenSharing() async {
    _screenStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.removeStream(_screenStream!);
    _peerConnection?.addStream(_localStream!);
    _localRenderer.srcObject = _localStream;
    setState(() => _isSharingScreen = false);
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _localStream?.dispose();
    _screenStream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Call')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
                    Expanded(child: RTCVideoView(_remoteRenderer)),
                  ],
                ),
                if (_hasCameraError)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Chip(
                      label: const Text('Camera not available'),
                      backgroundColor: Colors.red.withOpacity(0.7),
                    ),
                  ),
                if (_hasMicError)
                  Positioned(
                    top: 50,
                    left: 20,
                    child: Chip(
                      label: const Text('Microphone not available'),
                      backgroundColor: Colors.red.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: toggleScreenSharing,
                  child: Text(_isSharingScreen ? 'Stop Sharing' : 'Share Screen'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}