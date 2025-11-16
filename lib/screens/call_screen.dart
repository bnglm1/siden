// call_screen.dart - RENDERER BAŞLATMA SORUNU ÇÖZÜLDÜ
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:siden/services/call_manager.dart';

class CallScreen extends StatefulWidget {
  final bool isVideoCall;
  final String? otherUserName;
  final CallManager callManager;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.isVideoCall,
    this.otherUserName,
    required this.callManager,
    this.isIncoming = false,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _isConnected = false;
  String _callStatus = 'Bağlanıyor...';
  Duration _callDuration = Duration.zero;
  late Timer _callTimer;
  bool _isEndingCall = false;
  bool _areRenderersInitialized = false; // YENİ: Renderer durumu takibi

  // Callback'ler için stream subscription'lar
  StreamSubscription<MediaStream>? _remoteStreamSubscription;
  StreamSubscription<bool>? _callEndedSubscription;
  StreamSubscription<String>? _callErrorSubscription;
  StreamSubscription<bool>? _callConnectedSubscription;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
  }

  // RENDERER BAŞLATMA İŞLEMİ İYİLEŞTİRİLDİ
  Future<void> _initializeRenderers() async {
    try {
      print('Rendererlar başlatılıyor...');
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      setState(() {
        _areRenderersInitialized = true;
      });

      print('Rendererlar başarıyla başlatıldı');
      _setupLocalStream();
      _setupCallManager();
      _startCallTimer();
    } catch (e) {
      print('Renderer başlatma hatası: $e');
      _showErrorDialog('Video bileşenleri başlatılamadı: ${e.toString()}');
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_isConnected && mounted) {
        setState(() {
          _callDuration = _callDuration + Duration(seconds: 1);
          _callStatus = _formatDuration(_callDuration);
        });
      }
    });
  }

  // GÜVENLİ STREAM ATAMA METODU - YENİ
  void _safeSetLocalStream() {
    if (!_areRenderersInitialized) {
      print('Rendererlar henüz hazır değil, local stream atama erteleniyor');
      return;
    }

    if (widget.callManager.localStream != null) {
      try {
        _localRenderer.srcObject = widget.callManager.localStream;
        print('Local stream başarıyla atandı');
      } catch (e) {
        print('Local stream atama hatası: $e');
      }
    }
  }

  // GÜVENLİ UZAK STREAM ATAMA METODU - YENİ
  void _safeSetRemoteStream(MediaStream remoteStream) {
    if (!_areRenderersInitialized) {
      print('Rendererlar henüz hazır değil, remote stream atama erteleniyor');
      return;
    }

    try {
      _remoteRenderer.srcObject = remoteStream;
      print('Remote stream başarıyla atandı');
    } catch (e) {
      print('Remote stream atama hatası: $e');
    }
  }

  void _setupLocalStream() {
    _safeSetLocalStream();
  }

  void _setupCallManager() {
    // Uzak stream geldiğinde - İYİLEŞTİRİLDİ
    _remoteStreamSubscription =
        widget.callManager.remoteStreamStream.listen((remoteStream) {
      if (mounted) {
        setState(() {
          _safeSetRemoteStream(remoteStream);
          _isConnected = true;
          _callStatus = _formatDuration(_callDuration);
        });
      }
    });

    // Arama sonlandığında
    _callEndedSubscription = widget.callManager.callEndedStream.listen((_) {
      if (mounted && !_isEndingCall) {
        _safeNavigateBack();
      }
    });

    // Hata durumunda
    _callErrorSubscription = widget.callManager.callErrorStream.listen((error) {
      if (mounted) {
        setState(() {
          _callStatus = 'Hata: $error';
        });
        _showErrorDialog(error);
      }
    });

    // Arama bağlandığında
    _callConnectedSubscription =
        widget.callManager.callConnectedStream.listen((_) {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _callStatus = _formatDuration(_callDuration);
        });
      }
    });

    // Eğer gelen arama ise, renderer'ları hemen kur - İYİLEŞTİRİLDİ
    if (widget.isIncoming && _areRenderersInitialized) {
      _setupLocalStream();
      if (widget.callManager.remoteStream != null) {
        _safeSetRemoteStream(widget.callManager.remoteStream!);
        setState(() {
          _isConnected = true;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Arama Hatası'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => _safeNavigateBack(),
            child: Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // GÜVENLİ GERİ DÖNÜŞ METODU
  void _safeNavigateBack() {
    if (_isEndingCall) return;

    _isEndingCall = true;
    _callTimer.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Chat ekranına dön
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Uzak video (görüntülü aramada) - İYİLEŞTİRİLDİ
            if (widget.isVideoCall && _isConnected && _areRenderersInitialized)
              RTCVideoView(_remoteRenderer)
            else
              _buildBackground(),

            // Üst bilgi
            _buildHeader(),

            // Yerel video (görüntülü aramada) - İYİLEŞTİRİLDİ
            if (widget.isVideoCall && _areRenderersInitialized)
              Positioned(
                top: 80,
                right: 20,
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(_localRenderer),
                  ),
                ),
              ),

            // Kontrol butonları
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.blue.shade900, Colors.purple.shade900],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Profil resmi/avatar
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.shade600,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Icon(Icons.person, color: Colors.white, size: 60),
          ),
          SizedBox(height: 20),
          Text(
            widget.otherUserName ?? 'Aranan Kişi',
            style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Text(
            _isConnected ? _formatDuration(_callDuration) : _callStatus,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          if (!_isConnected) ...[
            SizedBox(height: 20),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _endCall,
          ),
          SizedBox(width: 10),
          Text(
            widget.isVideoCall ? 'Görüntülü Arama' : 'Sesli Arama',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          Spacer(),
          if (widget.isVideoCall)
            IconButton(
              icon: Icon(
                _isCameraOn ? Icons.videocam : Icons.videocam_off,
                color: Colors.white,
              ),
              onPressed: _toggleCamera,
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mikrofon
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            backgroundColor:
                _isMuted ? Colors.red : Colors.grey.withOpacity(0.7),
            onPressed: _toggleMute,
          ),

          // Sonlandır
          _buildControlButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: _endCall,
            isEndCall: true,
          ),

          // Kamera (sadece görüntülü aramada)
          if (widget.isVideoCall)
            _buildControlButton(
              icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
              backgroundColor:
                  _isCameraOn ? Colors.grey.withOpacity(0.7) : Colors.red,
              onPressed: _toggleCamera,
            ),

          // Hoparlör
          _buildControlButton(
            icon: Icons.volume_up,
            backgroundColor: Colors.grey.withOpacity(0.7),
            onPressed: _toggleSpeaker,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    bool isEndCall = false,
  }) {
    return CircleAvatar(
      radius: isEndCall ? 35 : 30,
      backgroundColor: backgroundColor,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: isEndCall ? 30 : 24),
        onPressed: onPressed,
      ),
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    widget.callManager.toggleMute(_isMuted);
  }

  void _toggleCamera() {
    setState(() {
      _isCameraOn = !_isCameraOn;
    });
    widget.callManager.toggleCamera(_isCameraOn);
  }

  void _toggleSpeaker() {
    // Hoparlör kontrolü buraya eklenecek
    // widget.callManager.toggleSpeaker();
  }

  void _endCall() {
    if (_isEndingCall) return;

    _isEndingCall = true;
    _callTimer.cancel();
    widget.callManager.endCall();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    print('CallScreen dispose ediliyor...');
    _isEndingCall = true;
    _callTimer.cancel();
    _remoteStreamSubscription?.cancel();
    _callEndedSubscription?.cancel();
    _callErrorSubscription?.cancel();
    _callConnectedSubscription?.cancel();

    // RENDERER DISPOSE İYİLEŞTİRİLDİ
    try {
      _localRenderer.dispose();
      _remoteRenderer.dispose();
      print('Rendererlar başarıyla dispose edildi');
    } catch (e) {
      print('Renderer dispose hatası: $e');
    }

    super.dispose();
  }
}
