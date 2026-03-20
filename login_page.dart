import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'guest_category_page.dart';
import 'owner_home_page.dart';
import '../state/cart_state.dart';
import '../state/realtime_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String ownerPasscode = '1'; // ← 好きな番号に変更
  static const int _ownerUnlockTapTarget = 5;
  int _ownerUnlockTapCount = 0;
  bool _isOwnerLoginVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RealtimeState>().connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _onLogoTapped,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/rk_service_logo.png',
                    width: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Column(
                      children: [
                        Icon(Icons.local_bar, size: 48),
                        SizedBox(height: 8),
                        Text(
                          'RK SERVICE',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              child: const Text('ゲストで入る（席番号）'),
              onPressed: () => _guestLogin(context),
            ),
            const SizedBox(height: 20),
            if (_isOwnerLoginVisible)
              ElevatedButton(
                child: const Text('オーナーで入る（パスコード）'),
                onPressed: () => _ownerLogin(context),
              ),
          ],
        ),
      ),
    );
  }

  void _onLogoTapped() {
    if (_isOwnerLoginVisible) return;

    _ownerUnlockTapCount++;
    if (_ownerUnlockTapCount < _ownerUnlockTapTarget) return;

    setState(() {
      _isOwnerLoginVisible = true;
      _ownerUnlockTapCount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('オーナーログインを表示しました')),
    );
  }

  Future<void> _guestLogin(BuildContext context) async {
    final ctrl = TextEditingController();

    final table = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('席番号を入力'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '例：A / VIP1 / T12'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (table == null || table.isEmpty) return;
    if (!mounted) return;

    context.read<AppState>().loginAsGuest(table);
    context.read<CartState>().clear();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GuestCategoryPage()),
    );
  }

  Future<void> _ownerLogin(BuildContext context) async {
    final ctrl = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('パスコード入力'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '****'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (code == null) return;
    if (!mounted) return;

    if (code != ownerPasscode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パスコードが違います')),
      );
      return;
    }

    context.read<AppState>().loginAsOwner();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OwnerHomePage()),
    );
  }
}