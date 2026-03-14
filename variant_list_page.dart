import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/cart_state.dart';
import '../utils/price_format.dart';

class VariantListPage extends StatelessWidget {
  final String category;
  final String brandName;
  final List variants;

  const VariantListPage({
    super.key,
    required this.category,
    required this.brandName,
    required this.variants,
  });

  void _showAddedToCartNotice(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label をカートに追加しました'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.watch<AppState>().mode == UserMode.owner;
    final cart = context.watch<CartState>();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          brandName,
          style: const TextStyle(
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: variants.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final v = variants[index] as Map<String, dynamic>;
          return _VariantRow(
            label: (v['label'] ?? '').toString(),
            price: (v['price'] as num?)?.toInt() ?? 0,
            onTap: isOwner
                ? null
                : () {
                    cart.add(
                      category: category,
                      brand: brandName,
                      label: (v['label'] ?? '').toString(),
                      price: (v['price'] as num?)?.toInt() ?? 0,
                      printGroup: (v['printGroup'] ?? 'kitchen').toString(),
                    );
                    _showAddedToCartNotice(
                      context,
                      (v['label'] ?? '').toString(),
                    );
                  },
          );
        },
      ),
      bottomNavigationBar: isOwner
          ? null
          : SafeArea(
              top: false,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '合計: ${formatYen(cart.total)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  final String label;
  final int price;
  final VoidCallback? onTap;

  const _VariantRow({
    required this.label,
    required this.price,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade700),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                formatYen(price),
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}