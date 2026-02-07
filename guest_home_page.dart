import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/menu_data.dart';

class GuestHomePage extends StatefulWidget {
  const GuestHomePage({super.key});

  @override
  State<GuestHomePage> createState() => _GuestHomePageState();
}

class _GuestHomePageState extends State<GuestHomePage> {
  String selectedCategory = 'おすすめ';

  // 注文状態（ゲスト専用）
  final Map<String, int> order = {};

  @override
  Widget build(BuildContext context) {
    final menuData = context.watch<MenuData>();

    // ===== ★重要①：選択中カテゴリの自動補正 =====
    if (menuData.categories.isNotEmpty &&
        !menuData.categories.contains(selectedCategory) &&
        selectedCategory != 'おすすめ') {
      selectedCategory = menuData.categories.first;
    }

    // ===== ★重要②：「おすすめ」は全商品表示 =====
    final filteredMenu = selectedCategory == 'おすすめ'
        ? menuData.items
        : menuData.items
            .where((item) => item['category'] == selectedCategory)
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Column(
          children: [
            // ===== 上部カテゴリバー =====
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6B4E2E),
                    Color(0xFFB08A57),
                  ],
                ),
              ),
              child: Row(
                children: [
                  // 固定の「おすすめ」
                  _CategoryTab(
                    text: 'おすすめ',
                    selected: selectedCategory == 'おすすめ',
                    onTap: () {
                      setState(() {
                        selectedCategory = 'おすすめ';
                      });
                    },
                  ),

                  // オーナー追加カテゴリ
                  ...menuData.categories.map((cat) {
                    return _CategoryTab(
                      text: cat,
                      selected: selectedCategory == cat,
                      onTap: () {
                        setState(() {
                          selectedCategory = cat;
                        });
                      },
                    );
                  })
                ],
              ),
            ),

            // ===== メインエリア =====
            Expanded(
              child: Row(
                children: [
                  // --- 左：メニューGrid ---
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: GridView.builder(
                          key: ValueKey(selectedCategory),
                          itemCount: filteredMenu.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemBuilder: (context, index) {
                            final item = filteredMenu[index];
                            final count = order[item['name']] ?? 0;

                            return _MenuGridItem(
                              name: item['name'],
                              price: item['price'],
                              count: count,
                              onAdd: () {
                                setState(() {
                                  order[item['name']] = count + 1;
                                });
                              },
                              onRemove: () {
                                if (count > 0) {
                                  setState(() {
                                    order[item['name']] = count - 1;
                                  });
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // --- 右：注文パネル ---
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '注文内容',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(),

                          Expanded(
                            child: ListView(
                              children: order.entries
                                  .where((e) => e.value > 0)
                                  .map((e) {
                                final item = menuData.items.firstWhere(
                                  (m) => m['name'] == e.key,
                                );
                                return _OrderRow(
                                  name: e.key,
                                  count: e.value,
                                  price: item['price'],
                                );
                              }).toList(),
                            ),
                          ),

                          const Divider(),

                          Text(
                            '合計 ${_totalPrice(menuData)} 円',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _totalPrice(MenuData menuData) {
    int sum = 0;
    order.forEach((name, count) {
      final item = menuData.items.firstWhere((m) => m['name'] == name);
      sum += (item['price'] as int) * count;
    });
    return sum;
  }
}

// ===== カテゴリタブ =====
class _CategoryTab extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ===== メニューカード =====
class _MenuGridItem extends StatelessWidget {
  final String name;
  final int price;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _MenuGridItem({
    required this.name,
    required this.price,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.wine_bar, size: 48),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$price 円'),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle),
                onPressed: count > 0 ? onRemove : null,
              ),
              Text(count.toString()),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: onAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== 注文行 =====
class _OrderRow extends StatelessWidget {
  final String name;
  final int count;
  final int price;

  const _OrderRow({
    required this.name,
    required this.count,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text('$name × $count')),
          Text('${price * count}円'),
        ],
      ),
    );
  }
}
