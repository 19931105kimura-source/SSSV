import 'package:flutter/material.dart';
import 'brand_list_page.dart';

class CategoryTopPage extends StatelessWidget {
  const CategoryTopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'BARCELONA',
          style: TextStyle(
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _WideCategory(
              title: 'シャンパン',
              subtitle: 'Champagne',
              onTap: () => _go(context, 'ボトル'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MidCategory(
                    title: '白ワイン',
                    subtitle: 'White Wine',
                    onTap: () => _go(context, 'ボトル'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MidCategory(
                    title: '赤ワイン',
                    subtitle: 'Red Wine',
                    onTap: () => _go(context, 'ボトル'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: const [
                _SmallCategory('飲み放題'),
                _SmallCategory('ゲストドリンク'),
                _SmallCategory('ピッチャー'),
                _SmallCategory('キャストオリシャン'),
                _SmallCategory('ノンアルコール'),
                _SmallCategory('フード'),
                _SmallCategory('割り物'),
                _SmallCategory('その他'),
                _SmallCategory('交換物'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandListPage(category: category),
      ),
    );
  }
}

// =============================
// 以下：不足していたWidget達
// =============================

class _WideCategory extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WideCategory({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade800,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MidCategory extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MidCategory({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade700,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SmallCategory extends StatelessWidget {
  final String title;
  const _SmallCategory(this.title);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
