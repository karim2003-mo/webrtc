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
  final RTCVideoRenderer _remoterenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCRtpSender? videoSender;
  final FirebaseDataSource _dataSource = FirebaseDataSource();
  late RTCPeerConnection pc;
  Map<String, RTCPeerConnection> pcMap = {};
    Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoterenderer.initialize();
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
    pc=await createPeerConnection(config);
    
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
  Future<void> startHost() async{
    final result = await _getUserMedia();
    _localRenderer.srcObject = _localStream;
    final listen= await _dataSource.onNewListener(roomId);
    listen.snapshots().listen((snapshot) async {
      print("fromonNewListener==============================${snapshot.docs.length}");
      if (snapshot.docs.isNotEmpty) {
        final participantId = snapshot.docs.first.id;
        print("fromonNewListener==============================$participantId");
        pcMap[participantId] = pc;
        print("listener has been added to pcMap");
    final offer=await pcMap[participantId]!.createOffer();
    await pcMap[participantId]!.setLocalDescription(offer);
    await _dataSource.pushOffer(roomId: roomId, offer: offer.toMap(),hostId: hostId , listenerId: participantId);

    pcMap[participantId]!.onIceCandidate = (RTCIceCandidate candidate) async {
      if (candidate != null) {
        await _dataSource.sendHostIceCandidates(roomId: roomId,hostId:hostId, candidate: candidate , listenerId: participantId);
      }
    };
        _localStream!.getTracks().forEach((track) {
          pcMap[participantId]!.addTrack(track, _localStream!);
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
    
    print("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%");
        await Future.delayed(Duration(seconds: 5), () {
  // Code to run after 2 seconds
  print("This runs after 2 seconds");
});
    if (pc!=null) {
      print("Participant already exists, skipping initialization.");
    }else{
      print("Participant doesn't exist, skipping initialization.");
    }
      final offer=await _dataSource.getoffer(hostId: hostId, roomId: roomId, listenerId: participantId);
      await pc.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
      final answer=await pc.createAnswer();
      await _dataSource.sendListeneranswer(roomId: roomId, answer: answer.toMap(),participantId: participantId);
      await pc.setLocalDescription(answer);
    pc.onIceCandidate = (RTCIceCandidate candidate) async {
      if (candidate != null) {
        await _dataSource.sendListenerIceCandidates(roomId: roomId, listenerId: participantId, candidate: candidate);
      }
    };
    if(offer!=null){
    }
    final candcollection= await _dataSource.getHostIceCandidates(hostId: hostId, roomId: roomId, listenerId: participantId);
    candcollection.snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        if (doc.exists) {
          final candidate = RTCIceCandidate(
            doc['candidate'],
            doc['sdpMid'],
            doc['sdpMLineIndex'],
          );
          pc.addCandidate(candidate);
        }
      }
    });
    pc.onTrack = (RTCTrackEvent event) {
      setState(() {
        _remoterenderer.srcObject = event.streams[0];
      });
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
          child: RTCVideoView((widget.isHost)?_localRenderer:_remoterenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
          ))],

        )
      ),
    );
  }
}