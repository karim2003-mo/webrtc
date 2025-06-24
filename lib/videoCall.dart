// ignore_for_file: unused_local_variable, unnecessary_null_comparison
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:websocket/firebase_data_source.dart';
class VideoCallScreen extends StatefulWidget {
  final String? roomId;
  final bool isHost;
  const VideoCallScreen({super.key ,this.roomId , required this.isHost});
  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}
class _VideoCallScreenState extends State<VideoCallScreen> {
      final config ={
      'iceServers': [{'urls':[ 'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
        'stun:stun3.l.google.com:19302',
        'stun:stun4.l.google.com:19302']}],
    };
  bool enablecamera=false;
  bool enableMicrophone=false;
  late String roomId;
  late String hostId;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  MediaStream? _screenStreem;
  RTCRtpSender? videoSender;
  final FirebaseDataSource _dataSource = FirebaseDataSource();
  Map<String, RTCPeerConnection> pcMap = {};
    Future<void> initRenderers() async {
    await _localRenderer.initialize();
  }
  getRoomAndSessionId() async{
    if(widget.isHost){
    roomId =await _dataSource.createSession();
    hostId= await _dataSource.createHostId(roomId);
    print("fromgetRoomAndSessionId==============================$roomId");
  }else{
    roomId=widget.roomId!;
    hostId= await _dataSource.getHostId(roomId);
  }
  }
  @override
void initState() {
  super.initState();
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await getRoomAndSessionId();
    await initRenderers();
    
    if (widget.isHost==true) {
      await startHost();
    } else {
      await startListener();
    }
  });
}
  Future<Map<String , bool>> _checkDevices() async{
    bool hasCamera = false;
    bool hasMicrophone = false;
    final devices = await navigator.mediaDevices.enumerateDevices();
    for (MediaDeviceInfo device in devices) {
      hasMicrophone=devices.any((d) => d.kind == 'audioinput');
      hasCamera = devices.any((d) => d.kind == 'videoinput');
    }
    return {
      'hasCamera': hasCamera,
      'hasMicrophone': hasMicrophone,
    };

  }
    Future<Map<String , dynamic>> _getUserMedia() async {
      final hasDevice= await _checkDevices();
      print("hasDevice==============================${hasDevice['hasCamera']}");
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': hasDevice['hasCamera'],
      'audio': hasDevice['hasMicrophone'],
    });
    _localRenderer.srcObject = _localStream;
    return hasDevice;
  }
  Future<void> _shareScreen() async{
    _screenStreem = await navigator.mediaDevices.getDisplayMedia({
      'video': true,
      'audio': true,
    });
    final combinedStream = await createLocalMediaStream('combined');
    _screenStreem!.getTracks().forEach((track) {
      combinedStream.addTrack(track);
    });
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        combinedStream.addTrack(track);
      });
    }
    setState(() {
    _localRenderer.srcObject = _screenStreem;
    videoSender!.replaceTrack(
      _screenStreem!.getVideoTracks()[0]
    );
    for(var track in combinedStream.getTracks()){
      for(var participantId in pcMap.keys.toList()){
        pcMap[participantId]!.addTrack(track, combinedStream);
      }
    }});
  }
  Future<void> startHost() async{
    final result = await _getUserMedia();
    _localRenderer.srcObject = _localStream;
    final listen= await _dataSource.onNewListener(roomId);
    listen.snapshots().listen((snapshot) async {
      print("fromonNewListener==============================${snapshot.docs.length}");
      if (snapshot.docs.isNotEmpty) {
        final participantId = snapshot.docs.first.id;
        print("fromonNewListener==============================$participantId");
        final pc=await createPeerConnection(config);
        pcMap[participantId] = pc;
        print("listener has been added to pcMap");
    final offer=await pcMap[participantId]!.createOffer();
    await pcMap[participantId]!.setLocalDescription(offer);
    await _dataSource.pushOffer(roomId: roomId, offer: offer.toMap(),hostId: hostId , listenerId: participantId);

    pcMap[participantId]!.onIceCandidate = (RTCIceCandidate candidate) async {
      if (candidate != null) {
        await _dataSource.sendHostIceCandidates(roomId: roomId,hostId:hostId, candidate: candidate);
      }
    };
        _localStream!.getTracks().forEach((track) {
          pc.addTrack(track, _localStream!);
        });
            final candcollection= await _dataSource.getListenerIceCandidates(roomId, participantId);
    candcollection.snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['candidate'] != null) {
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          pcMap[participantId]!.addCandidate(candidate);
        }
      }
    });
    final answerSnapshot = await _dataSource.getListenerAnswer(roomId, participantId);
    answerSnapshot.listen((snapshot) async {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data['answer'] != null) {
          final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
          await pcMap[participantId]!.setRemoteDescription(answer);
        }
      }
    });
      }
    });



  }
  Future<void> startListener() async{
    final participantId=await _dataSource.addListener(roomId);
    print("fromstartListener==============================$participantId");
    print("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%");
    print("fromstartListener----------------room Id is ==============================$roomId");
    
      final offer=await _dataSource.getoffer(hostId: hostId, roomId: roomId, listenerId: participantId);
    print("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%");
        await Future.delayed(Duration(seconds: 10), () {
  // Code to run after 2 seconds
  print("This runs after 2 seconds");
});
    if (pcMap.containsKey(participantId)) {
      print("Participant already exists, skipping initialization.");
    }else{
      print("Participant doesn't exist, skipping initialization.");
    }
      await pcMap[participantId]?.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
      final answer=await pcMap[participantId]!.createAnswer();
      await _dataSource.sendListeneranswer(roomId: roomId, answer: answer.toMap(),participantId: participantId);
      await pcMap[participantId]!.setLocalDescription(answer);
    pcMap[participantId]!.onIceCandidate = (RTCIceCandidate candidate) async {
      if (candidate != null) {
        await _dataSource.sendListenerIceCandidates(roomId: roomId, listenerId: participantId, candidate: candidate);
      }
    };
    if(offer!=null){
    }
    final candcollection= await _dataSource.getHostIceCandidates(roomId, hostId);
    candcollection.snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['candidate'] != null) {
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          pcMap[participantId]!.addCandidate(candidate);
        }
      }
    });
    pcMap[participantId]!.onTrack = (RTCTrackEvent event) {
        _localRenderer.srcObject = event.streams[0];
    };
  }
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Call'),
      ),
      body: Center(
        child:Column(
          children: [Expanded(child: Container(width: size.width*0.8,
          child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
          ))],

        )
      ),
    );
  }
}