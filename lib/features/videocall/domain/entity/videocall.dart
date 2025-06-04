class CallParams {
  final bool isCaller;
  final String callerId;
  final String calleeId;
  final bool withVideo;

  CallParams({
    required this.isCaller,
    required this.callerId,
    required this.calleeId,
    required this.withVideo,
  });
}
