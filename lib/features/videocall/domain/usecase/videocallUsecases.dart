import '../entity/videocall.dart';
import '../repository/videocall_repo.dart';

class StartVideoCallUseCase {
  final VideoCallRepo repository;

  StartVideoCallUseCase(this.repository);

  Future<void> execute(CallParams params) async{
    return repository.makeCall(params);
  }
}
class EndVideoCallUseCase {
  final VideoCallRepo repository;

  EndVideoCallUseCase(this.repository);

  Future<void> execute() async{
    return repository.endCall();
  }
}
class ToggleCameraUseCase {
  final VideoCallRepo repository;

  ToggleCameraUseCase(this.repository);

  Future<void> execute() async{
    return repository.toggleCamera();
  }
}
class ToggleMuteUseCase {
  final VideoCallRepo repository;

  ToggleMuteUseCase(this.repository);

  Future<void> execute() async{
    return repository.toggleMute();
  }
}