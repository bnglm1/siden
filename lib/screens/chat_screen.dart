import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class ChatPage extends StatefulWidget {
  final Map<String, dynamic> otherUserData;

  const ChatPage({required this.otherUserData});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSending = false;
  bool _isUploading = false;

  String get _chatRoomId {
    List<String> userIds = [_currentUser!.uid, widget.otherUserData['uid']];
    userIds.sort();
    return 'chat_${userIds[0]}_${userIds[1]}';
  }

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    _initializeDownloader();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeDownloader() async {
    await FlutterDownloader.initialize(debug: true);
  }

  // GELİŞTİRİLMİŞ: Aktif izin isteme fonksiyonu
  // Basit izin isteme fonksiyonu
  Future<bool> _requestPermissions({bool forDownload = false}) async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+ için photos izni
          PermissionStatus status = await Permission.photos.request();
          return status.isGranted;
        } else {
          // Android 12 ve altı için storage izni
          PermissionStatus status = await Permission.storage.request();
          return status.isGranted;
        }
      }

      // iOS için photos izni
      PermissionStatus status = await Permission.photos.request();
      return status.isGranted;
    } catch (e) {
      print('İzin istenirken hata: $e');
      return false;
    }
  }

  // Kalıcı red dialogu
  void _showPermanentDenialDialog({bool forDownload = false}) {
    String message = forDownload
        ? 'Resim indirmek için depolama izni gerekiyor. Lütfen ayarlardan izin verin.'
        : 'Resim göndermek için depolama izni gerekiyor. Lütfen ayarlardan izin verin.';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Depolama İzni Gerekli'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: Text('Ayarlar'),
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add({
        'type': 'text',
        'text': _messageController.text.trim(),
        'senderId': _currentUser!.uid,
        'senderName':
            _currentUser!.displayName ?? _currentUser!.email!.split('@')[0],
        'receiverId': widget.otherUserData['uid'],
        'timestamp': Timestamp.now(),
        'read': false,
        'deletedFor': [],
      });

      await _firestore.collection('chats').doc(_chatRoomId).set({
        'participants': [_currentUser!.uid, widget.otherUserData['uid']],
        'participantNames': {
          _currentUser!.uid:
              _currentUser!.displayName ?? _currentUser!.email!.split('@')[0],
          widget.otherUserData['uid']: widget.otherUserData['fullName'] ??
              widget.otherUserData['username'],
        },
        'lastMessage': _messageController.text.trim(),
        'lastMessageTime': Timestamp.now(),
        'lastMessageSender': _currentUser!.uid,
        'lastMessageRead': false,
      }, SetOptions(merge: true));

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      print('Mesaj gönderilirken hata: $e');
      _showCustomSnackBar(
        'Mesaj gönderilemedi',
        Icons.error_outline,
        Colors.red,
      );
    }

    setState(() {
      _isSending = false;
    });
  }

  // GELİŞTİRİLMİŞ: Resim seçme ve gönderme fonksiyonu
  Future<void> _pickAndSendImage() async {
    try {
      // Önce mevcut izin durumunu kontrol et ve aktif olarak izin iste
      bool hasPermission = await _requestPermissions(forDownload: false);

      if (!hasPermission) {
        // İzin verilmediyse, kullanıcıya bilgi ver ve işlemi sonlandır
        _showCustomSnackBar(
          'Resim göndermek için depolama izni gerekiyor',
          Icons.warning,
          Colors.orange,
        );
        return;
      }

      // İzin varsa resim seç
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        // Dosya boyutu kontrolü (max 10MB)
        final file = File(image.path);
        final stat = await file.stat();
        if (stat.size > 10 * 1024 * 1024) {
          _showCustomSnackBar(
            'Resim boyutu çok büyük (max 10MB)',
            Icons.error,
            Colors.red,
          );
          return;
        }

        await _uploadAndSendImage(file);
      }
    } on PlatformException catch (e) {
      // Platform-specific hataları ele al
      print('Platform hatası: $e');
      if (e.code == 'photo_access_denied') {
        _showCustomSnackBar(
          'Galeri erişim izni reddedildi',
          Icons.error,
          Colors.red,
        );
      } else {
        _showCustomSnackBar(
          'Resim seçilemedi',
          Icons.error_outline,
          Colors.red,
        );
      }
    } catch (e) {
      print('Resim seçilirken hata: $e');
      _showCustomSnackBar(
        'Resim seçilemedi: ${e.toString()}',
        Icons.error_outline,
        Colors.red,
      );
    }
  }

  // Resmi yükleme ve gönderme fonksiyonu
  Future<void> _uploadAndSendImage(File imageFile) async {
    setState(() {
      _isUploading = true;
    });

    try {
      String fileName =
          '${_chatRoomId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef =
          FirebaseStorage.instance.ref().child('chat_images/$fileName');

      // Metadata ile resim türünü belirt
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedBy': _currentUser!.uid,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      UploadTask uploadTask = storageRef.putFile(imageFile, metadata);

      // Yükleme durumunu dinle
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        print(
            'Yükleme durumu: ${snapshot.bytesTransferred}/${snapshot.totalBytes}');
      });

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      await _sendImageMessage(downloadUrl);
    } on FirebaseException catch (e) {
      print('Firebase Storage hatası: $e');
      String errorMessage = 'Resim yüklenirken hata oluştu';
      if (e.code == 'unauthorized') {
        errorMessage = 'Depolama erişim izni yok';
      } else if (e.code == 'canceled') {
        errorMessage = 'Yükleme iptal edildi';
      }
      _showCustomSnackBar(errorMessage, Icons.error, Colors.red);
    } catch (e) {
      print('Resim yüklenirken beklenmeyen hata: $e');
      _showCustomSnackBar(
        'Resim yüklenemedi: ${e.toString()}',
        Icons.error_outline,
        Colors.red,
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  // Resim mesajı gönderme fonksiyonu
  Future<void> _sendImageMessage(String imageUrl) async {
    try {
      await _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add({
        'type': 'image',
        'imageUrl': imageUrl,
        'text': '📷 Resim',
        'senderId': _currentUser!.uid,
        'senderName':
            _currentUser!.displayName ?? _currentUser!.email!.split('@')[0],
        'receiverId': widget.otherUserData['uid'],
        'timestamp': Timestamp.now(),
        'read': false,
        'deletedFor': [],
      });

      await _firestore.collection('chats').doc(_chatRoomId).set({
        'participants': [_currentUser!.uid, widget.otherUserData['uid']],
        'participantNames': {
          _currentUser!.uid:
              _currentUser!.displayName ?? _currentUser!.email!.split('@')[0],
          widget.otherUserData['uid']: widget.otherUserData['fullName'] ??
              widget.otherUserData['username'],
        },
        'lastMessage': '📷 Resim',
        'lastMessageTime': Timestamp.now(),
        'lastMessageSender': _currentUser!.uid,
        'lastMessageRead': false,
      }, SetOptions(merge: true));

      _scrollToBottom();
    } catch (e) {
      print('Resim mesajı gönderilirken hata: $e');
      _showCustomSnackBar(
        'Resim gönderilemedi',
        Icons.error_outline,
        Colors.red,
      );
    }
  }

  void _markMessagesAsRead() async {
    try {
      final unreadMessages = await _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .where('senderId', isEqualTo: widget.otherUserData['uid'])
          .where('read', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {'read': true});
      }

      if (unreadMessages.docs.isNotEmpty) {
        await batch.commit();

        await _firestore.collection('chats').doc(_chatRoomId).set({
          'lastMessageRead': true,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Mesajları okundu olarak işaretlerken hata: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showCustomSnackBar(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildAppBarPopupMenu() {
    return PopupMenuButton<String>(
      color: Colors.white,
      icon: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: Color(0xFF667eea),
          size: 22,
        ),
      ),
      offset: Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (value) {
        if (value == 'clear_chat') {
          _showClearChatDialog();
        } else if (value == 'user_info') {
          _showUserInfo();
        }
      },
      itemBuilder: (context) => [
        _buildPopupMenuItem(
          value: 'user_info',
          icon: Icons.person_outline_rounded,
          title: 'Profil Bilgisi',
          subtitle: 'Kullanıcı detaylarını görüntüle',
          gradient: LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          ),
          iconColor: Colors.white,
        ),
        _buildPopupMenuItem(
          value: 'clear_chat',
          icon: Icons.cleaning_services_rounded,
          title: 'Sohbeti Temizle',
          subtitle: 'Tüm mesaj geçmişini sil',
          gradient: LinearGradient(
            colors: [Color(0xFFff9a3c), Color(0xFFff6a00)],
          ),
          iconColor: Colors.white,
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildPopupMenuItem({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required Color iconColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 70,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.7),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFf0f0f0), // Neumorphism için uygun arka plan
      appBar: AppBar(
        backgroundColor: Color(0xFFf0f0f0),
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFf0f0f0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(-2, -2),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(3, 3),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF667eea),
              size: 20,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-3, -3),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(3, 3),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _getUserInitial(widget.otherUserData['fullName'] ?? ''),
                  style: TextStyle(
                    color: Color(0xFF667eea),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserData['fullName'] ?? 'Kullanıcı',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(widget.otherUserData['uid'])
                        .snapshots(),
                    builder: (context, snapshot) {
                      final isOnline = snapshot.data?['isOnline'] ?? false;
                      final lastSeen = snapshot.data?['lastSeen'];
                      return Text(
                        isOnline ? 'Çevrimiçi' : _getLastSeenText(lastSeen),
                        style: TextStyle(
                          fontSize: 12,
                          color: isOnline ? Colors.green : Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [_buildAppBarPopupMenu()],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .doc(_chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingIndicator();
                }

                if (snapshot.hasError) {
                  return _buildErrorWidget();
                }

                final messages = snapshot.data?.docs ?? [];

                final visibleMessages = messages.where((doc) {
                  final messageData = doc.data() as Map<String, dynamic>;
                  final deletedFor = List<String>.from(
                    messageData['deletedFor'] ?? [],
                  );
                  return !deletedFor.contains(_currentUser!.uid);
                }).toList();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markMessagesAsRead();
                });

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                if (visibleMessages.isEmpty) {
                  return _buildEmptyChat();
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: EdgeInsets.all(16),
                  physics: BouncingScrollPhysics(),
                  itemCount: visibleMessages.length,
                  itemBuilder: (context, index) {
                    final message = visibleMessages[index];
                    final messageData = message.data() as Map<String, dynamic>;
                    final isMe = messageData['senderId'] == _currentUser?.uid;
                    final isRead = messageData['read'] ?? false;
                    final messageType = messageData['type'] ?? 'text';
                    final imageUrl = messageData['imageUrl'];

                    return MessageBubble(
                      key: ValueKey(message.id),
                      text: messageData['text'],
                      isMe: isMe,
                      timestamp: messageData['timestamp'],
                      messageId: message.id,
                      senderId: messageData['senderId'],
                      isRead: isRead,
                      type: messageType,
                      imageUrl: imageUrl,
                      onCopy: () => _copyMessage(messageData['text']),
                      onDelete:
                          isMe ? () => _deleteMessageForMe(message.id) : null,
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Future<void> _deleteMessageForMe(String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .doc(messageId)
          .update({
        'deletedFor': FieldValue.arrayUnion([_currentUser!.uid]),
      });

      _showCustomSnackBar('Mesaj silindi', Icons.check_circle, Colors.green);
    } catch (e) {
      print('Mesaj silinirken hata: $e');
      _showCustomSnackBar(
        'Mesaj silinirken bir hata oluştu',
        Icons.error_outline,
        Colors.red,
      );
    }
  }

  Future<void> _clearAllMessagesForMe() async {
    try {
      final messagesSnapshot = await _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (final doc in messagesSnapshot.docs) {
        batch.update(doc.reference, {
          'deletedFor': FieldValue.arrayUnion([_currentUser!.uid]),
        });
      }
      await batch.commit();

      _showCustomSnackBar(
        'Tüm mesajlar silindi',
        Icons.check_circle,
        Colors.green,
      );
    } catch (e) {
      print('Mesajlar silinirken hata: $e');
      _showCustomSnackBar(
        'Mesajlar silinirken bir hata oluştu',
        Icons.error_outline,
        Colors.red,
      );
    }
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Color(0xFFf0f0f0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(-4, -4),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(4, 4),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Mesajlar yükleniyor...',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Color(0xFFf0f0f0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(-4, -4),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(4, 4),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 40,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Bir hata oluştu',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Mesajlar yüklenirken sorun oluştu',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFFf0f0f0),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(-3, -3),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(3, 3),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() {}),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    'Tekrar Dene',
                    style: TextStyle(
                      color: Color(0xFF667eea),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-6, -6),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(6, 6),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 50,
                color: Color(0xFF667eea),
              ),
            ),
            SizedBox(height: 28),
            Text(
              'Henüz mesaj yok',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'İlk mesajı siz göndererek sohbeti başlatın!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-4, -4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(4, 4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _messageController.text = 'Merhaba! 👋';
                    _sendMessage();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.waving_hand_rounded,
                            color: Color(0xFF667eea)),
                        SizedBox(width: 8),
                        Text(
                          'Merhaba Mesajı Gönder',
                          style: TextStyle(
                            color: Color(0xFF667eea),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFf0f0f0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Resim ekleme butonu
          Container(
            decoration: BoxDecoration(
              color: Color(0xFFf0f0f0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(-3, -3),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(3, 3),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isUploading ? null : _pickAndSendImage,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  width: 44,
                  height: 44,
                  child: Icon(
                    _isUploading
                        ? Icons.access_time_rounded
                        : Icons.photo_camera_rounded,
                    color: _isUploading ? Colors.grey : Color(0xFF667eea),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-3, -3),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(3, 3),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Mesajınızı yazın...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 15,
                        ),
                      ),
                      style: TextStyle(fontSize: 15),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  if (_isSending || _isUploading)
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF667eea),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFFf0f0f0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(-3, -3),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: Offset(3, 3),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSending ? null : _sendMessage,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  width: 50,
                  height: 50,
                  child: Icon(
                    _isSending ? Icons.access_time_rounded : Icons.send_rounded,
                    color: Color(0xFF667eea),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getUserInitial(String fullName) {
    if (fullName.isEmpty) return 'U';
    final names = fullName.split(' ');
    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    }
    return fullName.substring(0, 1).toUpperCase();
  }

  String _getLastSeenText(Timestamp? lastSeen) {
    if (lastSeen == null) return 'Çevrimdışı';

    final now = DateTime.now();
    final lastSeenTime = lastSeen.toDate();
    final difference = now.difference(lastSeenTime);

    if (difference.inSeconds < 60) return 'Az önce çevrimiçi';
    if (difference.inMinutes < 1) return 'Az önce';
    if (difference.inMinutes < 60) return '${difference.inMinutes} dk önce';
    if (difference.inHours < 24) return '${difference.inHours} saat önce';
    if (difference.inDays < 7) return '${difference.inDays} gün önce';

    final dateFormat =
        DateTime.now().year == lastSeenTime.year ? 'dd MMM' : 'dd MMM yyyy';
    return '${lastSeenTime.day} ${_getMonthName(lastSeenTime.month)} ${lastSeenTime.year != DateTime.now().year ? lastSeenTime.year : ''}'
        .trim();
  }

  String _getMonthName(int month) {
    const months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    return months[month - 1];
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showCustomSnackBar(
      'Mesaj panoya kopyalandı',
      Icons.check_circle,
      Colors.green,
    );
  }

  void _showClearChatDialog() {
    showDialog(context: context, builder: (context) => _buildClearChatDialog());
  }

  Widget _buildClearChatDialog() {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Color(0xFFf0f0f0),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.white,
              offset: Offset(-6, -6),
              blurRadius: 15,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: Offset(6, 6),
              blurRadius: 15,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-4, -4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(4, 4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.cleaning_services_rounded,
                color: Colors.orange,
                size: 36,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Sohbeti Temizle',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Tüm mesaj geçmişini sadece sizin için\nsilmek istediğinizden emin misiniz?\nKarşı taraf mesajları görmeye devam edecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFf0f0f0),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white,
                          offset: Offset(-3, -3),
                          blurRadius: 7,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          offset: Offset(3, 3),
                          blurRadius: 7,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              'İptal',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFf0f0f0),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white,
                          offset: Offset(-3, -3),
                          blurRadius: 7,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          offset: Offset(3, 3),
                          blurRadius: 7,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          _clearAllMessagesForMe();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              'Temizle',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showUserInfo() {
    showDialog(context: context, builder: (context) => _buildUserInfoDialog());
  }

  Widget _buildUserInfoDialog() {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Color(0xFFf0f0f0),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.white,
              offset: Offset(-6, -6),
              blurRadius: 15,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: Offset(6, 6),
              blurRadius: 15,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-4, -4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(4, 4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _getUserInitial(widget.otherUserData['fullName'] ?? ''),
                  style: TextStyle(
                    color: Color(0xFF667eea),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              widget.otherUserData['fullName'] ?? 'Kullanıcı',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '@${widget.otherUserData['username'] ?? 'kullanici'}',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-3, -3),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(3, 3),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        'Tamam',
                        style: TextStyle(
                          color: Color(0xFF667eea),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final Timestamp timestamp;
  final String messageId;
  final String senderId;
  final bool isRead;
  final VoidCallback? onDelete;
  final VoidCallback onCopy;
  final String type;
  final String? imageUrl;

  const MessageBubble({
    Key? key,
    required this.text,
    required this.isMe,
    required this.timestamp,
    required this.messageId,
    required this.senderId,
    required this.isRead,
    this.onDelete,
    required this.onCopy,
    this.type = 'text',
    this.imageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        _showMessageOptions(context);
      },
      onTap: type == 'image' ? () => _showFullScreenImage(context) : null,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe)
              Container(
                margin: EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  backgroundColor: Color(0xFFf0f0f0),
                  radius: 16,
                  child: Icon(
                    Icons.person_rounded,
                    color: Color(0xFF667eea),
                    size: 16,
                  ),
                ),
              ),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: type == 'text'
                    ? EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                    : EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? Color(0xFFf0f0f0) : Color(0xFFf0f0f0),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: isMe ? Radius.circular(20) : Radius.circular(4),
                    bottomRight:
                        isMe ? Radius.circular(4) : Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white,
                      offset: Offset(-3, -3),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: Offset(3, 3),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (type == 'text')
                      Text(
                        text,
                        style: TextStyle(
                          color: isMe ? Color(0xFF667eea) : Colors.black87,
                          fontSize: 15,
                        ),
                      )
                    else if (type == 'image')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl!,
                          placeholder: (context, url) => Container(
                            width: 200,
                            height: 200,
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF667eea)),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 200,
                            height: 200,
                            color: Colors.grey.shade300,
                            child:
                                Icon(Icons.error_outline, color: Colors.grey),
                          ),
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(timestamp.toDate()),
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isMe ? Color(0xFF667eea) : Colors.grey.shade600,
                          ),
                        ),
                        if (isMe) SizedBox(width: 6),
                        if (isMe)
                          Icon(
                            isRead ? Icons.done_all : Icons.done,
                            size: 14,
                            color: isRead
                                ? Colors.blue.shade200
                                : Color(0xFF667eea),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isMe)
              Container(
                margin: EdgeInsets.only(left: 8),
                child: CircleAvatar(
                  backgroundColor: Color(0xFFf0f0f0),
                  radius: 16,
                  child: Icon(
                    Icons.person_rounded,
                    color: Color(0xFF764ba2),
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Tam ekran resim görüntüleme
  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.download, color: Colors.white),
                onPressed: () {
                  final fileName =
                      'resim_${DateTime.now().millisecondsSinceEpoch}.jpg';
                  _downloadImage(context, imageUrl!, fileName);
                },
              ),
            ],
          ),
          body: Center(
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(imageUrl!),
              backgroundDecoration: BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
            ),
          ),
        ),
      ),
    );
  }

  // GELİŞTİRİLMİŞ: Resim indirme fonksiyonu
  // GELİŞTİRİLMİŞ: Resim indirme fonksiyonu - izin istemeden direkt indir
  // GELİŞTİRİLMİŞ: Resim indirme fonksiyonu - düzeltilmiş versiyon
  Future<void> _downloadImage(
      BuildContext context, String imageUrl, String fileName) async {
    try {
      // Dizin seçimi
      Directory? directory;

      if (Platform.isAndroid) {
        // Android için Downloads dizinini kullan
        directory = await getExternalStorageDirectory();
        String downloadsPath = directory!.path;

        // Downloads klasörüne kaydet
        String newPath = '';
        List<String> folders = downloadsPath.split('/');
        for (int i = 1; i < folders.length; i++) {
          String folder = folders[i];
          if (folder != 'Android') {
            newPath += '/$folder';
          } else {
            break;
          }
        }

        newPath = '$newPath/Download';
        directory = Directory(newPath);

        // Klasör yoksa oluştur
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      } else {
        // iOS için Documents directory
        directory = await getApplicationDocumentsDirectory();
      }

      // Dosya adını temizle
      fileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

      // Tam dosya yolu
      String filePath = '${directory.path}/$fileName';

      print('İndirme yolu: $filePath');
      print('URL: $imageUrl');

      // İndirme işlemi
      final taskId = await FlutterDownloader.enqueue(
        url: imageUrl,
        fileName: fileName,
        savedDir: directory.path,
        showNotification: true,
        openFileFromNotification: true,
        requiresStorageNotLow: false,
        saveInPublicStorage: true, // Android 10+ için public storage
      );

      if (taskId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resim indiriliyor...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // İndirme durumunu dinle
        FlutterDownloader.registerCallback((id, status, progress) {
          if (id == taskId) {
            print('İndirme durumu: $status, ilerleme: $progress%');

            if (status == DownloadTaskStatus.complete) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('✅ Resim başarıyla indirildi'),
                        SizedBox(height: 4),
                        Text(
                          'Yol: ${directory?.path}/$fileName',
                          style: TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 4),
                  ),
                );
              });
            } else if (status == DownloadTaskStatus.failed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ İndirme başarısız'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 3),
                  ),
                );
              });
            }
          }
        });
      } else {
        throw Exception('İndirme başlatılamadı');
      }
    } catch (e) {
      print('Resim indirilirken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ İndirme hatası: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // GELİŞTİRİLMİŞ: MessageBubble içindeki izin isteme fonksiyonu - CONTEXT PARAMETRESİ EKLENDİ
  Future<bool> _requestPermissions(BuildContext context,
      {bool forDownload = false}) async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;

        PermissionStatus status;
        if (androidInfo.version.sdkInt >= 33) {
          status = forDownload
              ? await Permission.storage.status
              : await Permission.photos.status;
        } else {
          status = await Permission.storage.status;
        }

        if (status.isGranted) return true;
        if (status.isDenied) {
          // AKTİF olarak izin iste
          if (androidInfo.version.sdkInt >= 33) {
            status = forDownload
                ? await Permission.storage.request()
                : await Permission.photos.request();
          } else {
            status = await Permission.storage.request();
          }
          return status.isGranted;
        }
        if (status.isPermanentlyDenied) {
          // Kalıcı red - ayarlara yönlendir
          _showPermanentDenialDialog(context, forDownload: forDownload);
          return false;
        }
        return false;
      }

      // iOS için
      PermissionStatus status;
      if (forDownload) {
        status = await Permission.storage.status;
        if (status.isDenied) {
          status = await Permission.storage.request();
        }
      } else {
        status = await Permission.photos.status;
        if (status.isDenied) {
          status = await Permission.photos.request();
        }
      }
      return status.isGranted;
    } catch (e) {
      print('İzin istenirken hata: $e');
      return false;
    }
  }

  // MessageBubble içindeki kalıcı red dialogu - CONTEXT PARAMETRESİ EKLENDİ
  void _showPermanentDenialDialog(BuildContext context,
      {bool forDownload = false}) {
    String message = forDownload
        ? 'Resim indirmek için depolama izni gerekiyor. Lütfen ayarlardan izin verin.'
        : 'Resim göndermek için depolama izni gerekiyor. Lütfen ayarlardan izin verin.';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Depolama İzni Gerekli'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: Text('Ayarlar'),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: EdgeInsets.only(top: 50),
        decoration: BoxDecoration(
          color: Color(0xFFf0f0f0),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 25,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Color(0xFFf0f0f0),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-3, -3),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: Offset(3, 3),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type == 'text' ? 'Mesaj' : 'Resim',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  if (type == 'text')
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade800,
                        height: 1.4,
                      ),
                    )
                  else
                    Container(
                      height: 100,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  if (type == 'text')
                    _buildOptionItem(
                      context: context,
                      icon: Icons.copy_rounded,
                      title: 'Mesajı Kopyala',
                      subtitle: 'Mesajı panoya kopyala',
                      color: Color(0xFF667eea),
                      onTap: () {
                        Navigator.pop(context);
                        onCopy();
                      },
                    ),
                  if (type == 'image') ...[
                    _buildOptionItem(
                      context: context,
                      icon: Icons.download_rounded,
                      title: 'Resmi İndir',
                      subtitle: 'Resmi cihazınıza kaydedin',
                      color: Color(0xFF667eea),
                      onTap: () {
                        Navigator.pop(context);
                        final fileName =
                            'resim_${DateTime.now().millisecondsSinceEpoch}.jpg';
                        _downloadImage(context, imageUrl!, fileName);
                      },
                    ),
                    SizedBox(height: 8),
                  ],
                  if (onDelete != null) ...[
                    SizedBox(height: 8),
                    _buildOptionItem(
                      context: context,
                      icon: Icons.delete_outline_rounded,
                      title: 'Mesajı Sil',
                      subtitle: 'Bu mesajı sadece sizden sil',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        onDelete!();
                      },
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 16),
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFFf0f0f0),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white,
                      offset: Offset(-3, -3),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: Offset(3, 3),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'İptal',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFFf0f0f0),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.white,
                offset: Offset(-3, -3),
                blurRadius: 5,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                offset: Offset(3, 3),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(0xFFf0f0f0),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white,
                      offset: Offset(-2, -2),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: Offset(2, 2),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: color.withOpacity(0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
