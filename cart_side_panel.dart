import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/cart_state.dart';
import '../state/order_state.dart';
import '../state/app_state.dart';
import '../utils/price_format.dart';


class CartPage extends StatelessWidget {
  const CartPage({super.key});

  static const bgColor = Color(0xFF0E0E0E);
  static const cardColor = Color(0xFF1A1A1A);
  static const accent = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final orderState = context.watch<OrderState>();
    final table = context.select<AppState, String?>((s) => s.guestTable);

    final canOrder =
        table != null && orderState.isActive(table);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E), // ← 追加
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('カート'),
      ),
      body: cart.items.isEmpty
          ? const Center(
              child: Text(
                'カートは空です',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.brand} / ${item.label}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  formatYen(item.price),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  onPressed: canOrder
                                      ? () => context
                                          .read<CartState>()
                                          .dec(item)
                                      : null,
                                ),
                                Text(
                                  '${item.qty}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: canOrder
                                      ? () => context
                                          .read<CartState>()
                                          .inc(item)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '合計',
                            style: TextStyle(color: Colors.white),
                          ),
                          const Spacer(),
                          Text(
                            formatYen(cart.total),
                            style: const TextStyle(
                              color: accent,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canOrder ? accent : Colors.grey,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: canOrder
                            ? () =>
                                _confirmOrder(context, cart)
                            : null,
                        child: Text(
                          canOrder ? '注文を確定する' : '受付終了',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmOrder(
    BuildContext context,
    CartState cart,
  ) async {
    final orderState = context.read<OrderState>();
    final table = context.read<AppState>().guestTable;

    if (table == null || !orderState.isActive(table)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この席は受付が終了しています')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('注文確認'),
        content:Text('合計 ${formatYen(cart.total)}\n注文を確定しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final sent = await orderState.addFromCart(cart, table);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? '注文を受け付けました'
                : '注文を確定できませんでした。通信状態を確認して再試行してください。',
          ),
        ),
      );
       if (sent) {
        if (sent) {
        Navigator.pop(context);
      }
      }
    }
  }
}
// =========================
// カートサイドパネルを開く（ゲスト共通）
// =========================
void openCartSidePanel(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CartPage(),
  );
}
