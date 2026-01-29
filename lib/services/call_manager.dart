import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

class CallManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _currentCallId;
  StreamSubscription<DocumentSnapshot>? _callSubscription;

  final StreamController<MediaStream> _remoteStreamController =
      StreamController<MediaStream>.broadcast();
  final StreamController<bool> _callEndedController =
      StreamController<bool>.broadcast();
  final StreamController<String> _callErrorController =
      StreamController<String>.broadcast();
  final StreamController<bool> _callConnectedController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>?> _incomingCallController =
      StreamController<Map<String, dynamic>?>.broadcast();

  Stream<MediaStream> get remoteStreamStream => _remoteStreamController.stream;
  Stream<bool> get callEndedStream => _callEndedController.stream;
  Stream<String> get callErrorStream => _callErrorController.stream;
  Stream<bool> get callConnectedStream => _callConnectedController.stream;
  Stream<Map<String, dynamic>?> get incomingCallStream =>
      _incomingCallController.stream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  Future<void> rejectCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'rejected',
        'endedAt': FieldValue.serverTimestamp(),
      });

      await _cleanUpCallData(callId);
    } catch (e) {
      await _cleanUpCallData(callId);
      rethrow;
    }
  }

  Future<void> _cleanUpCallData(String callId) async {
    try {
      await Future.delayed(Duration(seconds: 2));
      await _firestore.collection('calls').doc(callId).delete();
    } catch (e) {}
  }

  Future<bool> _requestPermissions(bool isVideoCall) async {
    try {
      if (isVideoCall) {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.camera,
          Permission.microphone,
        ].request();
        return (statuses[Permission.camera]?.isGranted ?? false) &&
            (statuses[Permission.microphone]?.isGranted ?? false);
      } else {
        PermissionStatus status = await Permission.microphone.request();
        return status.isGranted;
      }
    } catch (e) {
      _callErrorController.add('İzin istenirken hata oluştu');
      return false;
    }
  }

  Future<void> startCall(String receiverId, bool isVideoCall) async {
    try {
      bool hasPermissions = await _requestPermissions(isVideoCall);
      if (!hasPermissions) {
        throw Exception('Gerekli izinler alınamadı');
      }

      await _cleanUp();
      _currentCallId =
          'call_${DateTime.now().millisecondsSinceEpoch}_${_currentUser!.uid}';

      await _getUserMedia(isVideoCall);
      await _createPeerConnection();

      await _firestore.collection('calls').doc(_currentCallId).set({
        'callId': _currentCallId,
        'callerId': _currentUser!.uid,
        'receiverId': receiverId,
        'type': isVideoCall ? 'video' : 'audio',
        'status': 'calling',
        'timestamp': FieldValue.serverTimestamp(),
        'callerName': _currentUser!.displayName ?? _currentUser!.email,
      });

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await _firestore.collection('calls').doc(_currentCallId).update({
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type.toString().split('.').last
        }
      });

      _listenForCallUpdates(_currentCallId!);
    } catch (e) {
      if (_currentCallId != null) {
        await _cleanUpCallData(_currentCallId!);
      }
      await _cleanUp();
      rethrow;
    }
  }

  void listenForIncomingCalls() {
    if (_currentUser == null) return;

    _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: _currentUser!.uid)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] == 'calling' &&
              data['receiverId'] == _currentUser!.uid &&
              !_isCallExpired(data)) {
            data['callId'] = doc.id;
            _incomingCallController.add(data);
            return;
          }
        }
      }
    }, onError: (error) {});
  }

  bool _isCallExpired(Map<String, dynamic> callData) {
    final timestamp = callData['timestamp'] as Timestamp?;
    if (timestamp == null) return true;

    final callTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(callTime).inSeconds;

    if (difference > 60) {
      _cleanUpCallData(callData['callId']);
      return true;
    }
    return false;
  }

  Future<void> acceptCall(String callId) async {
    try {
      final callDoc = await _firestore.collection('calls').doc(callId).get();
      final callData = callDoc.data();

      if (callData == null) {
        throw Exception('Arama bulunamadı');
      }

      if (callData['status'] != 'calling') {
        throw Exception('Arama artık aktif değil');
      }

      final isVideoCall = callData['type'] == 'video';
      bool hasPermissions = await _requestPermissions(isVideoCall);
      if (!hasPermissions) {
        throw Exception('Gerekli izinler alınamadı');
      }

      await _cleanUp();
      _currentCallId = callId;
      await _getUserMedia(isVideoCall);
      await _createPeerConnection();

      await _firestore.collection('calls').doc(callId).update({
        'status': 'answered',
        'answeredAt': FieldValue.serverTimestamp(),
      });

      final offer = callData['offer'];
      if (offer != null) {
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(offer['sdp'], offer['type']));
      }

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await _firestore.collection('calls').doc(callId).update({
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type.toString().split('.').last
        }
      });

      _listenForCallUpdates(callId);
    } catch (e) {
      await _cleanUpCallData(callId);
      await _cleanUp();
      rethrow;
    }
  }

  void _listenForCallUpdates(String callId) {
    _callSubscription?.cancel();
    _callSubscription = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        await endCall();
        return;
      }

      final data = snapshot.data()!;

      try {
        if (data['answer'] != null && _peerConnection != null) {
          final answer = data['answer'];
          final currentRemoteDescription =
              await _peerConnection!.getRemoteDescription();
          if (currentRemoteDescription == null) {
            await _peerConnection!.setRemoteDescription(
                RTCSessionDescription(answer['sdp'], answer['type']));
          }
        }

        if (data['iceCandidates'] != null && _peerConnection != null) {
          final candidates = data['iceCandidates'] as List;
          for (var candidate in candidates) {
            try {
              await _peerConnection!.addCandidate(RTCIceCandidate(
                candidate['candidate'],
                candidate['sdpMid'] ?? '',
                candidate['sdpMLineIndex'] ?? 0,
              ));
            } catch (e) {}
          }
        }

        if (data['status'] == 'ended' ||
            data['status'] == 'rejected' ||
            data['status'] == 'missed') {
          await endCall();
        }
      } catch (e) {}
    });
  }

  Future<void> _getUserMedia(bool isVideoCall) async {
    try {
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideoCall
            ? {
                'width': 640,
                'height': 480,
                'frameRate': 30,
                'facingMode': 'user'
              }
            : false
      };

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      throw Exception('Kamera ve mikrofon erişimi reddedildi.');
    }
  }

  Future<void> _createPeerConnection() async {
    try {
      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan'
      };

      _peerConnection = await createPeerConnection(configuration);

      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      _peerConnection!.onAddStream = (stream) {
        _remoteStream = stream;
        _remoteStreamController.add(stream);
        _callConnectedController.add(true);
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null &&
            candidate.candidate!.isNotEmpty &&
            _currentCallId != null) {
          _firestore.collection('calls').doc(_currentCallId).update({
            'iceCandidates': FieldValue.arrayUnion([
              {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              }
            ])
          });
        }
      };

      _peerConnection!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          _callConnectedController.add(true);
        } else if (state ==
                RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          endCall();
        }
      };
    } catch (e) {
      throw Exception('Peer connection oluşturulamadı');
    }
  }

  Future<void> endCall() async {
    try {
      if (_currentCallId != null) {
        await _firestore.collection('calls').doc(_currentCallId).update({
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        });

        await _cleanUpCallData(_currentCallId!);
      }

      await _cleanUp();
      _callEndedController.add(true);
    } catch (e) {
      await _cleanUp();
      _callEndedController.add(true);
    }
  }

  Future<void> markAsMissedCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'missed',
        'endedAt': FieldValue.serverTimestamp(),
      });

      await _cleanUpCallData(callId);
      await _cleanUp();
    } catch (e) {
      await _cleanUpCallData(callId);
      await _cleanUp();
    }
  }

  void toggleMute(bool mute) {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        audioTracks.first.enabled = !mute;
      }
    }
  }

  void toggleCamera(bool enable) {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        videoTracks.first.enabled = enable;
      }
    }
  }

  void switchCamera() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        try {
          Helper.switchCamera(videoTracks.first);
        } catch (e) {}
      }
    }
  }

  Future<void> _cleanUp() async {
    try {
      _callSubscription?.cancel();
      _callSubscription = null;

      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream = null;
      }

      if (_remoteStream != null) {
        _remoteStream!.getTracks().forEach((track) => track.stop());
        _remoteStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      _currentCallId = null;
    } catch (e) {}
  }

  void dispose() {
    _cleanUp();
    _remoteStreamController.close();
    _callEndedController.close();
    _callErrorController.close();
    _callConnectedController.close();
    _incomingCallController.close();
  }
}
