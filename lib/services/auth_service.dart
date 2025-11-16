import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<User?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Kullanıcıyı çevrimiçi yap ve son giriş zamanını güncelle
      await _setUserOnlineStatus(userCredential.user!.uid, true);

      return userCredential.user;
    } catch (e) {
      rethrow;
    }
  }

  Future<User?> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String username,
    required String fullName,
  }) async {
    try {
      // Kullanıcıyı Firebase Auth ile oluştur
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user != null) {
        // Kullanıcı profilini güncelle - DÜZELTME: updateDisplayName yerine updateProfile kullan
        await user.updateProfile(displayName: fullName);

        // Kullanıcıyı yeniden yükle ki değişiklikler hemen görünsün
        await user.reload();

        // Firestore'da kullanıcı dokümanı oluştur
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'username': username,
          'email': email,
          'fullName': fullName,
          'createdAt': Timestamp.now(),
          'lastLogin': Timestamp.now(),
          'isOnline': true,
          'lastSeen': Timestamp.now(),
        });
      }

      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _setUserOnlineStatus(String uid, bool isOnline) async {
    await _firestore.collection('users').doc(uid).update({
      'isOnline': isOnline,
      'lastSeen': Timestamp.now(),
      if (isOnline) 'lastLogin': Timestamp.now(),
    });
  }

  Future<void> signOut() async {
    // Çıkış yaparken çevrimdışı durumuna geç
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _setUserOnlineStatus(user.uid, false);
    }

    await _firebaseAuth.signOut();
  }

  // Uygulama durumu değişiklikleri için
  Future<void> setAppUserStatus(bool isOnline) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _setUserOnlineStatus(user.uid, isOnline);
    }
  }

  User? get currentUser => _firebaseAuth.currentUser;

  Future<void> sendPasswordResetEmail(String email) async {
    await _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  // Kullanıcı adının kullanılabilir olup olmadığını kontrol et
  Future<bool> isUsernameAvailable(String username) async {
    final querySnapshot = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    return querySnapshot.docs.isEmpty;
  }

  // Kullanıcı profilini güncelleme metodu - YENİ EKLENDİ
  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await user.updateProfile(
        displayName: displayName,
        photoURL: photoURL,
      );
      await user.reload();
    }
  }

  // Kullanıcı bilgilerini getirme metodu - YENİ EKLENDİ
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Mevcut kullanıcının verilerini getir - YENİ EKLENDİ
  Future<Map<String, dynamic>?> getCurrentUserData() async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      return await getUserData(user.uid);
    }
    return null;
  }
}
