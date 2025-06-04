import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:websocket/features/videocall/domain/entity/call_status.dart';

import '../entity/videocall.dart';

abstract class VideoCallRepo {
  Future<void> init();
  Future<void> makeCall(CallParams params);
  Future<void> endCall();
  Future<void> toggleCamera();
  Future<void> toggleMute();
  Stream<CallStatus> get callStatus;
  Stream<MediaStream?> get localStream;
  Stream<MediaStream?> get remoteStream;
}