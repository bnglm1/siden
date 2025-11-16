// incoming_call_screen.dart - DÜZELTİLMİŞ VERSİYON
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:siden/services/call_manager.dart';
import 'call_screen.dart';
import 'chat_screen.dart'; // Chat ekranını import edin

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> callData;
  final CallManager callManager;

  const IncomingCallScreen({
    Key? key,
    required this.callData,
    required this.callManager,
  }) : super(key: key);

  @override
  _IncomingCallScreenState createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isActive = true;
  StreamSubscription<bool>? _callEndedSubscription;
  StreamSubscription<String>? _callErrorSubscription;
  Timer? _callTimeoutTimer;
  String? _callerName;
  int _remainingSeconds = 60;
  bool _isProcessing = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    print("IncomingCallScreen initialized");

    // Titreşim animasyonu
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _setupCallListeners();
    _startCallTimeoutTimer();
    _loadCallerName();
  }

  void _setupCallListeners() {
    _callEndedSubscription = widget.callManager.callEndedStream.listen((_) {
      print("Call ended stream received");
      if (!_isActive) return;
      _safePopToHome();
    });

    _callErrorSubscription = widget.callManager.callErrorStream.listen((error) {
      print("Call error stream received: $error");
      if (!_isActive) return;
      _safeShowErrorAndPop(error);
    });
  }

  void _startCallTimeoutTimer() {
    _callTimeoutTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds > 0) {
        _safeSetState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _safeMarkAsMissedCall();
      }
    });
  }

  void _safeSetState(VoidCallback callback) {
    if (_isActive && mounted) {
      setState(callback);
    }
  }

  Future<void> _loadCallerName() async {
    try {
      final name = await _getCallerName(widget.callData['callerId']);
      if (_isActive && mounted) {
        setState(() {
          _callerName = name;
        });
      }
    } catch (e) {
      print('Kullanıcı adı yüklenirken hata: $e');
    }
  }

  // BASİT VE GÜVENLİ NAVİGASYON - Ana sayfaya dön
  void _safePopToHome() {
    if (!_isActive) return;

    print("Safe pop to home started");
    _isActive = false;
    _callTimeoutTimer?.cancel();
    _animationController.dispose();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Tüm sayfaları temizle ve ana sayfaya dön
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  // YENİ METOD: Chat ekranına yönlendirme
  void _safeNavigateToChat() {
    if (!_isActive) return;

    print("Safe navigate to chat started");
    _isActive = false;
    _callTimeoutTimer?.cancel();
    _animationController.dispose();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          // otherUserData oluştur - ChatPage'in beklediği yapıda
          final otherUserData = {
            'uid': widget.callData['callerId'],
            'fullName':
                _callerName ?? widget.callData['callerName'] ?? 'Arayan',
            'username': widget.callData['callerName'] ?? 'arayan',
            // Diğer gerekli alanları ekleyebilirsiniz
          };

          // ChatPage'e yönlendir
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => ChatPage(otherUserData: otherUserData),
            ),
            (Route<dynamic> route) => false,
          );
        } catch (e) {
          print('Chat ekranına yönlendirme hatası: $e');
          // Hata durumunda ana sayfaya dön
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    });
  }

  void _safeShowErrorAndPop(String error) {
    if (!_isActive) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        _safePopToHome();
      }
    });
  }

  void _safeMarkAsMissedCall() {
    if (!_isActive || _isProcessing) return;

    print("Safe mark as missed call started");
    _isProcessing = true;

    _safeSetState(() {
      _isActive = false;
    });

    widget.callManager.markAsMissedCall(widget.callData['callId']);
    _safeNavigateToChat(); // Kaçırılan aramadan sonra chat ekranına git
  }

  void _safeRejectCall() {
    if (!_isActive || _isProcessing) return;

    print("Safe reject call started");
    _isProcessing = true;

    _safeSetState(() {
      _isActive = false;
    });

    widget.callManager.rejectCall(widget.callData['callId']);
    _safePopToHome(); // Sadece ana sayfaya dön
  }

  Future<void> _safeAcceptCall() async {
    if (!_isActive || _isProcessing) return;

    print("Safe accept call started");
    _isProcessing = true;

    _safeSetState(() {
      _isActive = false;
    });

    try {
      _callTimeoutTimer?.cancel();
      await Future.delayed(Duration(milliseconds: 500));

      await widget.callManager.acceptCall(widget.callData['callId']);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final String displayName = _callerName ??
              widget.callData['callerName'] ??
              widget.callData['callerId'];

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => CallScreen(
                callManager: widget.callManager,
                isVideoCall: widget.callData['type'] == 'video',
                otherUserName: displayName,
                isIncoming: true,
              ),
            ),
          );
        }
      });
    } catch (e) {
      print('Arama kabul hatası: $e');
      _safeShowErrorAndPop('Arama kabul edilemedi: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActive) {
      return SizedBox.shrink();
    }

    final isVideoCall = widget.callData['type'] == 'video';
    final String displayName = _callerName ??
        widget.callData['callerName'] ??
        widget.callData['callerId'];

    return WillPopScope(
      onWillPop: () async {
        // Geri butonuna basıldığında aramayı reddet
        _safeRejectCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Container(
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
              children: [
                // Üst kısım - Geri butonu ve süre
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _safeRejectCall,
                        child: Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Spacer(),
                      Text(
                        '$_remainingSeconds saniye',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                // Ana içerik - Ortalanmış
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Gelen ${isVideoCall ? 'Görüntülü' : 'Sesli'} Arama',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      SizedBox(height: 40),

                      // Titreşim efekti ile profil resmi
                      ScaleTransition(
                        scale: _animation,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.shade600,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 15,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 80,
                          ),
                        ),
                      ),

                      SizedBox(height: 30),
                      Column(
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Aranıyor...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Alt kısım - Butonlar
                Container(
                  padding: EdgeInsets.only(bottom: 60, left: 20, right: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                        icon: Icons.call_end,
                        backgroundColor: Colors.red,
                        onPressed: _safeRejectCall,
                        label: 'Reddet',
                      ),
                      _buildActionButton(
                        icon: Icons.call,
                        backgroundColor: Colors.green,
                        onPressed: _safeAcceptCall,
                        label: 'Kabul Et',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    required String label,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Future<String> _getCallerName(String callerId) async {
    try {
      return widget.callData['callerName'] ?? callerId;
    } catch (e) {
      print('Kullanıcı adı alma hatası: $e');
      return widget.callData['callerName'] ?? callerId;
    }
  }

  @override
  void dispose() {
    print("IncomingCallScreen disposed");
    _isActive = false;
    _isProcessing = true;

    _callEndedSubscription?.cancel();
    _callErrorSubscription?.cancel();
    _callTimeoutTimer?.cancel();
    _animationController.dispose();

    super.dispose();
  }
}
