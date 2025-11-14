import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  // Kullanıcı adını email formatına çeviren yardımcı fonksiyon
  String _convertUsernameToEmail(String username) {
    return '$username@modernchat.com';
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorDialog('Şifreler eşleşmiyor');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      // Kullanıcı adını email formatına çevir
      String email = _convertUsernameToEmail(_usernameController.text.trim());
      String password = _passwordController.text.trim();
      String fullName = _fullNameController.text.trim();

      await authService.createUserWithEmailAndPassword(
        email: email,
        password: password,
        username: _usernameController.text.trim(),
        fullName: fullName,
      );

      _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Kayıt sırasında bir hata oluştu';

      if (e.code == 'email-already-in-use') {
        errorMessage = 'Bu kullanıcı adı zaten kullanılıyor';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Şifre çok zayıf, lütfen daha güçlü bir şifre seçin';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Geçersiz kullanıcı adı formatı';
      } else if (e.code == 'operation-not-allowed') {
        errorMessage = 'Bu işlem şu anda desteklenmiyor';
      }

      _showErrorDialog(errorMessage);
    } catch (e) {
      _showErrorDialog('Beklenmeyen bir hata oluştu: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Color(0xFFf0f0f0),
            borderRadius: BorderRadius.circular(25),
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
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Color(0xFFf0f0f0),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white,
                      offset: Offset(-4, -4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: Offset(4, 4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(Icons.error_outline, color: Colors.red, size: 30),
              ),
              SizedBox(height: 16),
              Text(
                'Hata',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                ),
              ),
              SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFFf0f0f0),
                  borderRadius: BorderRadius.circular(15),
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
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      child: Text(
                        'Tamam',
                        style: TextStyle(
                          color: Color(0xFF667eea),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Color(0xFFf0f0f0),
            borderRadius: BorderRadius.circular(25),
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
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Color(0xFFf0f0f0),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white,
                      offset: Offset(-4, -4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: Offset(4, 4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(Icons.check_circle, color: Colors.green, size: 30),
              ),
              SizedBox(height: 16),
              Text(
                'Başarılı',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Kayıt başarılı! Hoş geldiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Kullanıcı adınız: ${_usernameController.text}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFFf0f0f0),
                  borderRadius: BorderRadius.circular(15),
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
                    onTap: () {
                      Navigator.of(context).pop();
                      _navigateToLogin();
                    },
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      child: Text(
                        'Giriş Yap',
                        style: TextStyle(
                          color: Color(0xFF667eea),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.of(context).pop();
  }

  // Kullanıcı adı validasyonu
  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Lütfen kullanıcı adınızı girin';
    }
    if (value.length < 3) {
      return 'Kullanıcı adı en az 3 karakter olmalıdır';
    }
    if (value.length > 20) {
      return 'Kullanıcı adı en fazla 20 karakter olabilir';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'Kullanıcı adı sadece harf, rakam ve alt çizgi içerebilir';
    }
    return null;
  }

  // Şifre validasyonu
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Lütfen şifrenizi girin';
    }
    if (value.length < 6) {
      return 'Şifre en az 6 karakter olmalıdır';
    }
    if (value.length > 50) {
      return 'Şifre çok uzun';
    }
    return null;
  }

  // Tam ad validasyonu
  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Lütfen adınızı ve soyadınızı girin';
    }
    if (value.length < 2) {
      return 'Ad soyad en az 2 karakter olmalıdır';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFf0f0f0), // Neumorphism arka plan
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                // Üst Bar
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFf0f0f0),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-4, -4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        offset: Offset(4, 4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
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
                            onTap: _navigateToLogin,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.arrow_back,
                                  color: Color(0xFF667eea)),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Text(
                        'Kayıt Ol',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 40),

                // Form Container
                Container(
                  padding: EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Color(0xFFf0f0f0),
                    borderRadius: BorderRadius.circular(25),
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Text(
                          'Yeni Hesap Oluştur',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667eea),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Aşağıdaki bilgileri doldurun',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        SizedBox(height: 30),

                        // Tam Ad Alanı
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFf0f0f0),
                            borderRadius: BorderRadius.circular(15),
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
                          child: TextFormField(
                            controller: _fullNameController,
                            decoration: InputDecoration(
                              labelText: 'Ad Soyad',
                              prefixIcon: Icon(
                                Icons.person_outline,
                                color: Color(0xFF667eea),
                              ),
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              hintText: 'Ali Yılmaz',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: _validateFullName,
                          ),
                        ),
                        SizedBox(height: 20),

                        // Kullanıcı Adı Alanı
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFf0f0f0),
                            borderRadius: BorderRadius.circular(15),
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
                          child: TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'Kullanıcı Adı',
                              prefixIcon: Icon(
                                Icons.alternate_email,
                                color: Color(0xFF667eea),
                              ),
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              hintText: 'kullanici_adi',
                              helperText:
                                  'Sadece harf, rakam ve alt çizgi kullanabilirsiniz',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: _validateUsername,
                          ),
                        ),
                        SizedBox(height: 20),

                        // Şifre Alanı
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFf0f0f0),
                            borderRadius: BorderRadius.circular(15),
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
                          child: TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              prefixIcon: Icon(
                                Icons.lock,
                                color: Color(0xFF667eea),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Color(0xFF667eea),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              helperText: 'En az 6 karakter olmalıdır',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            validator: _validatePassword,
                          ),
                        ),
                        SizedBox(height: 20),

                        // Şifre Tekrar Alanı
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFf0f0f0),
                            borderRadius: BorderRadius.circular(15),
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
                          child: TextFormField(
                            controller: _confirmPasswordController,
                            decoration: InputDecoration(
                              labelText: 'Şifre Tekrar',
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: Color(0xFF667eea),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Color(0xFF667eea),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Lütfen şifrenizi tekrar girin';
                              }
                              if (value != _passwordController.text) {
                                return 'Şifreler eşleşmiyor';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _register(),
                          ),
                        ),
                        SizedBox(height: 30),

                        // Bilgilendirme Metni
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Color(0xFFf0f0f0),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white,
                                offset: Offset(-3, -3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.1),
                                offset: Offset(3, 3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
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
                                      color: Colors.blue.withOpacity(0.1),
                                      offset: Offset(2, 2),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.info_outline,
                                  color: Color(0xFF667eea),
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Giriş yaparken kullanıcı adınızı ve şifrenizi kullanacaksınız',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),

                        // Kayıt Butonu
                        if (_isLoading)
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: Color(0xFFf0f0f0),
                              borderRadius: BorderRadius.circular(15),
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
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF667eea),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Color(0xFFf0f0f0),
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white,
                                  offset: Offset(-4, -4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  offset: Offset(4, 4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _register,
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  width: double.infinity,
                                  height: 50,
                                  child: Center(
                                    child: Text(
                                      'Hesap Oluştur',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF667eea),
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
                ),

                SizedBox(height: 30),

                // Giriş Yap Bölümü
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color(0xFFf0f0f0),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-4, -4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        offset: Offset(4, 4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Zaten hesabınız var mı?',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFf0f0f0),
                          borderRadius: BorderRadius.circular(20),
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
                            onTap: _navigateToLogin,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 16,
                              ),
                              child: Text(
                                'Giriş Yap',
                                style: TextStyle(
                                  color: Color(0xFF667eea),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
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

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }
}
