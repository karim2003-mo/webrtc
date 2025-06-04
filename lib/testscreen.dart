import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

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
  bool _isAudioEnabled = true;
  bool _isVideoEnabled = true;
  bool _isCallActive = false;
  final _firestore = FirebaseFirestore.instance;
  
  // Stream subscriptions for cleanup
  StreamSubscription? _roomSubscription;
  StreamSubscription? _candidatesSubscription;

  @override
  void initState() {
    super.initState();
    _initRenderers().then((_) => _startCall());
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
    } catch (e) {
      print('Renderer initialization error: $e');
      _showErrorDialog('Failed to initialize video renderers');
    }
  }

  Future<void> _startCall() async {
    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(config);

      // Try to get media with video first
      try {
        _localStream = await _getUserMedia(withVideo: true);
        if (mounted) {
          _localRenderer.srcObject = _localStream;
          _localStream?.getTracks().forEach((track) {
            _peerConnection!.addTrack(track, _localStream!);
          });
        }
      } catch (e) {
        print('Video error: $e');
        // Try without video if video fails
        try {
          _localStream = await _getUserMedia(withVideo: false);
          if (mounted) {
            _localRenderer.srcObject = _localStream;
            _localStream?.getTracks().forEach((track) {
              _peerConnection!.addTrack(track, _localStream!);
            });
            setState(() => _hasCameraError = true);
          }
        } catch (audioError) {
          print('Audio error: $audioError');
          if (mounted) {
            setState(() {
              _hasCameraError = true;
              _hasMicError = true;
            });
          }
          _showErrorDialog('Cannot access camera or microphone');
          return;
        }
      }

      _setupPeerConnectionListeners();
      
      if (widget.isCaller) {
        await _createOffer();
      } else {
        await _listenForOffer();
      }
      
      setState(() => _isCallActive = true);
    } catch (e) {
      print('Call setup error: $e');
      _showErrorDialog('Failed to start call: ${e.toString()}');
    }
  }

  Future<MediaStream> _getUserMedia({bool withVideo = true}) async {
    try {
      final constraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
        },
        'video': withVideo ? {
          'width': {'ideal': 1280, 'max': 1920},
          'height': {'ideal': 720, 'max': 1080},
          'facingMode': 'user',
          'frameRate': {'ideal': 30},
        } : false,
      };

      final media = await navigator.mediaDevices.getUserMedia(constraints);
      return media;
    } catch (e) {
      if (e.toString().toLowerCase().contains('audio')) {
        if (mounted) setState(() => _hasMicError = true);
      }
      rethrow;
    }
  }

  void _setupPeerConnectionListeners() {
    _peerConnection!.onIceCandidate = (candidate) async {
      if (candidate.candidate != null) {
        final roomRef = _firestore.collection('rooms').doc(widget.roomId);
        final candidatesCollection = widget.isCaller 
            ? roomRef.collection('callerCandidates')
            : roomRef.collection('calleeCandidates');

        final json = {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'timestamp': FieldValue.serverTimestamp(),
        };

        try {
          await candidatesCollection.add(json);
        } catch (e) {
          print('Error adding ICE candidate: $e');
        }
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      print('Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (mounted) {
          _showErrorDialog('Connection lost. Please try again.');
        }
      }
    };
  }

  Future<void> _createOffer() async {
    try {
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);
      
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      
      await roomRef.set({
        'offer': offer.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Listen for answer
      _roomSubscription = roomRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        if (data != null && data.containsKey('answer') && _peerConnection != null) {
          try {
            final answer = data['answer'];
            final remoteDesc = RTCSessionDescription(answer['sdp'], answer['type']);
            await _peerConnection!.setRemoteDescription(remoteDesc);
          } catch (e) {
            print('Error setting remote description: $e');
          }
        }
      });

      // Listen for callee ICE candidates
      _candidatesSubscription = roomRef.collection('calleeCandidates')
          .orderBy('timestamp')
          .snapshots()
          .listen((snapshot) {
        _processCandidates(snapshot.docs);
      });
    } catch (e) {
      print('Create offer error: $e');
      _showErrorDialog('Failed to create offer');
    }
  }

  Future<void> _listenForOffer() async {
    try {
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);
      final snapshot = await roomRef.get();

      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data.containsKey('offer')) {
          final offer = data['offer'];
          final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
          await _peerConnection!.setRemoteDescription(remoteDesc);

          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          
          await roomRef.update({
            'answer': answer.toMap(),
            'answeredAt': FieldValue.serverTimestamp(),
          });

          // Listen for caller ICE candidates
          _candidatesSubscription = roomRef.collection('callerCandidates')
              .orderBy('timestamp')
              .snapshots()
              .listen((snapshot) {
            _processCandidates(snapshot.docs);
          });
        }
      }
    } catch (e) {
      print('Listen for offer error: $e');
      _showErrorDialog('Failed to join call');
    }
  }

  void _processCandidates(List<DocumentSnapshot> docs) {
    for (final doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        _peerConnection?.addCandidate(candidate);
      } catch (e) {
        print('Error processing candidate: $e');
      }
    }
  }

  Future<void> toggleScreenSharing() async {
    if (!_isCallActive) return;
    
    try {
      if (_isSharingScreen) {
        await _stopScreenSharing();
      } else {
        await _startScreenSharing();
      }
    } catch (e) {
      print('Screen sharing error: $e');
      _showErrorDialog('Screen sharing error: ${e.toString()}');
    }
  }

  Future<void> _startScreenSharing() async {
    try {
      final constraints = {
        'video': {
          'width': {'ideal': 1920, 'max': 1920},
          'height': {'ideal': 1080, 'max': 1080},
          'frameRate': {'ideal': 15, 'max': 30},
        },
        'audio': false,
      };

      _screenStream = await navigator.mediaDevices.getDisplayMedia(constraints);
      
      if (_screenStream != null && mounted) {
        // Replace video track
        final videoTrack = _screenStream!.getVideoTracks().first;
        final sender = await _peerConnection?.getSenders().then((senders) =>
            senders.firstWhere((s) => s.track?.kind == 'video'));
        
        if (sender != null) {
          await sender.replaceTrack(videoTrack);
        }
        
        _localRenderer.srcObject = _screenStream;

        // Handle screen share end
        videoTrack.onEnded = () {
          if (mounted && _isSharingScreen) {
            toggleScreenSharing();
          }
        };

        setState(() => _isSharingScreen = true);
      }
    } catch (e) {
      print('Start screen sharing error: $e');
      rethrow;
    }
  }

  Future<void> _stopScreenSharing() async {
    try {
      if (_screenStream != null) {
        _screenStream!.getTracks().forEach((track) => track.stop());
        
        // Replace with camera track
        if (_localStream != null) {
          final videoTrack = _localStream!.getVideoTracks().isNotEmpty 
              ? _localStream!.getVideoTracks().first 
              : null;
          
          if (videoTrack != null) {
            final sender = await _peerConnection?.getSenders().then((senders) =>
                senders.firstWhere((s) => s.track?.kind == 'video'));
            
            if (sender != null) {
              await sender.replaceTrack(videoTrack);
            }
          }
          
          _localRenderer.srcObject = _localStream;
        }
        
        _screenStream = null;
        setState(() => _isSharingScreen = false);
      }
    } catch (e) {
      print('Stop screen sharing error: $e');
      rethrow;
    }
  }

  Future<void> _toggleAudio() async {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final enabled = !_isAudioEnabled;
        audioTracks.first.enabled = enabled;
        setState(() => _isAudioEnabled = enabled);
      }
    }
  }

  Future<void> _toggleVideo() async {
    if (_localStream != null && !_isSharingScreen) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final enabled = !_isVideoEnabled;
        videoTracks.first.enabled = enabled;
        setState(() => _isVideoEnabled = enabled);
      }
    }
  }

  Future<void> _endCall() async {
    try {
      // Clean up room data
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);
      await roomRef.delete();
    } catch (e) {
      print('Error deleting room: $e');
    }
    
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endCall();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Cancel subscriptions
    _roomSubscription?.cancel();
    _candidatesSubscription?.cancel();
    
    // Dispose renderers
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    
    // Close peer connection
    _peerConnection?.close();
    _peerConnection = null;
    
    // Stop media streams
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream?.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _endCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('Video Call - ${widget.roomId}'),
          backgroundColor: Colors.black87,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _endCall,
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  // Main video views
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                          ),
                          child: RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                          ),
                          child: RTCVideoView(
                            _remoteRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Error indicators
                  if (_hasCameraError)
                    Positioned(
                      top: 20,
                      left: 20,
                      child: Chip(
                        label: const Text('Camera unavailable', style: TextStyle(color: Colors.white)),
                        backgroundColor: Colors.red.withOpacity(0.8),
                        avatar: const Icon(Icons.videocam_off, color: Colors.white, size: 16),
                      ),
                    ),
                  if (_hasMicError)
                    Positioned(
                      top: _hasCameraError ? 60 : 20,
                      left: 20,
                      child: Chip(
                        label: const Text('Microphone unavailable', style: TextStyle(color: Colors.white)),
                        backgroundColor: Colors.red.withOpacity(0.8),
                        avatar: const Icon(Icons.mic_off, color: Colors.white, size: 16),
                      ),
                    ),
                  // Status indicators
                  if (_isSharingScreen)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Chip(
                        label: const Text('Sharing Screen', style: TextStyle(color: Colors.white)),
                        backgroundColor: Colors.green.withOpacity(0.8),
                        avatar: const Icon(Icons.screen_share, color: Colors.white, size: 16),
                      ),
                    ),
                ],
              ),
            ),
            // Control buttons
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.black87,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: _isAudioEnabled ? Icons.mic : Icons.mic_off,
                    onPressed: _toggleAudio,
                    isActive: _isAudioEnabled,
                  ),
                  _buildControlButton(
                    icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    onPressed: _isSharingScreen ? null : _toggleVideo,
                    isActive: _isVideoEnabled,
                  ),
                  _buildControlButton(
                    icon: _isSharingScreen ? Icons.stop_screen_share : Icons.screen_share,
                    onPressed: toggleScreenSharing,
                    isActive: _isSharingScreen,
                  ),
                  _buildControlButton(
                    icon: Icons.call_end,
                    onPressed: _endCall,
                    isActive: false,
                    backgroundColor: Colors.red,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isActive,
    Color? backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? (isActive ? Colors.blue : Colors.grey),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        iconSize: 28,
      ),
    );
  }
}