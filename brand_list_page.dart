import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../utils/price_format.dart';
import '../data/menu_data.dart';
import '../state/app_state.dart';
import '../state/cart_state.dart';

import 'cart_side_panel.dart';
import 'guest_order_history_page.dart';
import 'owner_add_item_sheet.dart';

class BrandListPage extends StatefulWidget {
  final String category;
  const BrandListPage({super.key, required this.category});

  @override
  State<BrandListPage> createState() => _BrandListPageState();
}

class _BrandListPageState extends State<BrandListPage> {
  Map<String, dynamic>? selectedBrand;

  void openCartSidePanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CartPage(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.watch<AppState>().mode == UserMode.owner;
    final menuData = context.watch<MenuData>();
    final cart = context.watch<CartState>();

    final table =
        context.select<AppState, String?>((s) => s.guestTable) ?? '-';

    final brands = menuData.items
        .where((i) =>
            i['category'] == widget.category &&
            (i['name'] as String).isNotEmpty)
        .toList();

    final variants = selectedBrand == null
        ? <dynamic>[]
        : (selectedBrand!['variants'] as List);

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/Image.png',
            repeat: ImageRepeat.repeat,
            fit: BoxFit.none,
            color: Colors.black.withValues(alpha: 0.32),
            colorBlendMode: BlendMode.darken,
          ),
        ),
        Positioned.fill(
          child: Container(
            color: const Color(0xFF0F0F12).withValues(alpha: 0.78),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leadingWidth: isOwner ? null : 170,
            leading: isOwner
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BackButton(),
                      _TableBadge(text: table),
                    ],
                  ),
            title: Text(widget.category),
            actions: [
              if (!isOwner) ...[
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: () => openCartSidePanel(context),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(
                      '¥${NumberFormat('#,###').format(cart.total)}',
                    ),
                  ),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.receipt_long),
                tooltip: '注文履歴',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const GuestOrderHistoryPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Row(
            children: [
              // =========================
              // 左：銘柄一覧（brands）
              // =========================
              SizedBox(
                width: 260,
                child: isOwner
                    ? ReorderableListView.builder(
                        itemCount: brands.length + 1,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex == brands.length) return;
                          if (newIndex > brands.length) {
                            newIndex = brands.length;
                          }
                          if (newIndex > oldIndex) newIndex--;
                          menuData.reorderBrands(
                              widget.category, oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          if (index == brands.length) {
                            return Padding(
                              key: const ValueKey('__add_brand__'),
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _PlusRow(
                                  text: '銘柄を追加',
                                  onTap: () => _addBrand(context),
                                ),
                              ),
                            );
                          }

                          final b = brands[index];

                          return ListTile(
                            key: ValueKey(b),
                            title: Text(
                              b['name'],
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selected: selectedBrand == b,
                            onTap: () => setState(() => selectedBrand = b),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _renameBrand(context, b);
                                } else if (v == 'delete') {
                                  menuData.removeBrand(b);
                                  if (selectedBrand == b) {
                                    setState(() => selectedBrand = null);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('名前変更')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    '削除',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : ListView(
                        children: brands.map((b) {
                          return ListTile(
                            title: Text(b['name']),
                            selected: selectedBrand == b,
                            onTap: () =>
                                setState(() => selectedBrand = b),
                          );
                        }).toList(),
                      ),
              ),

              // =========================
              // 右：種類（variants）
              // =========================
              Expanded(
                child: selectedBrand == null
                    ? const Center(child: Text('銘柄を選択してください'))
                    : isOwner
                        ? ReorderableListView.builder(
                            itemCount: variants.length + 1,
                            onReorder: (oldIndex, newIndex) {
                              if (oldIndex == variants.length) return;
                              if (newIndex > variants.length) {
                                newIndex = variants.length;
                              }
                              if (newIndex > oldIndex) newIndex--;
                              menuData.reorderVariants(
                                  selectedBrand!, oldIndex, newIndex);
                            },
                            itemBuilder: (context, index) {
                              if (index == variants.length) {
                                return Padding(
                                  key:
                                      const ValueKey('__add_variant__'),
                                  padding:
                                      const EdgeInsets.fromLTRB(
                                          16, 8, 16, 16),
                                  child: Align(
                                    alignment:
                                        Alignment.centerLeft,
                                    child: _PlusRow(
                                      text: '種類を追加',
                                      onTap: () =>
                                          _addVariant(context),
                                    ),
                                  ),
                                );
                              }

                              final v = variants[index]
                                  as Map<String, dynamic>;

                              return ListTile(
                                key: ValueKey(v),
                                title: Text(v['label']),
                                subtitle:
                                    Text(formatYen(v['price'])),
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) =>
                                        OwnerAddItemSheet(
                                      label: v['label'],
                                    ),
                                  );
                                },
                                trailing:
                                    PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == 'edit') {
                                      _editVariant(context, v);
                                    } else if (val ==
                                        'delete') {
                                      menuData.removeVariant(
                                          selectedBrand!, v);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'edit',
                                        child: Text('編集')),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        '削除',
                                        style: TextStyle(
                                            color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : ListView.separated(
                            itemCount: variants.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final v = variants[index]
                                  as Map<String, dynamic>;

                              return ListTile(
                                title: Text(v['label']),
                                 trailing: Text(
  formatYen(v['price']),
  style: const TextStyle(
    fontSize: 22,              // ← 大きく
    fontWeight: FontWeight.bold, // ← 太く
  ),
),

                                onTap: () {
                                  cart.add(
                                    category: widget.category,
                                    brand:
                                        selectedBrand!['name'],
                                    label: v['label'],
                                    price: v['price'],
                                  );
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================
  // dialogs
  // =========================

  void _addBrand(BuildContext context) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('銘柄追加'),
        content: TextField(controller: c),
        actions: [
          ElevatedButton(
            onPressed: () {
              context
                  .read<MenuData>()
                  .addBrand(widget.category, c.text);
              Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  void _renameBrand(BuildContext context, Map<String, dynamic> b) {
    final c = TextEditingController(text: b['name']);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('名前変更'),
        content: TextField(controller: c),
        actions: [
          ElevatedButton(
            onPressed: () {
              context
                  .read<MenuData>()
                  .renameBrand(b, c.text);
              Navigator.pop(context);
            },
            child: const Text('変更'),
          ),
        ],
      ),
    );
  }
  //////////////////////////////////////
  void _addVariant(BuildContext context) {
  if (selectedBrand == null) return;

  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  String printGroup = 'kitchen'; // ★ デフォルト

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('種類追加'),
      content: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名前'),
              ),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: '価格'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '印刷先',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              RadioListTile<String>(
                title: const Text('厨房（通常）'),
                value: 'kitchen',
                groupValue: printGroup,
                onChanged: (v) => setState(() => printGroup = v!),
              ),
              RadioListTile<String>(
                title: const Text('レジ（特殊・高額）'),
                value: 'register',
                groupValue: printGroup,
                onChanged: (v) => setState(() => printGroup = v!),
              ),
            ],
          );
        },
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            final price = int.tryParse(priceCtrl.text) ?? 0;

            context.read<MenuData>().addVariant(
              selectedBrand!,
              nameCtrl.text,
              price,
              printGroup: printGroup, // ★ 追加
            );

            Navigator.pop(context);
          },
          child: const Text('追加'),
        ),
      ],
    ),
  );
}

   ////////////////////////////
  void _editVariant(BuildContext context, Map<String, dynamic> v) {
  final nameCtrl = TextEditingController(text: v['label']);
  final priceCtrl =
      TextEditingController(text: v['price'].toString());

  String printGroup = v['printGroup'] ?? 'kitchen';

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('編集'),
      content: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '印刷先',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              RadioListTile<String>(
                title: const Text('厨房（通常）'),
                value: 'kitchen',
                groupValue: printGroup,
                onChanged: (v) => setState(() => printGroup = v!),
              ),
              RadioListTile<String>(
                title: const Text('レジ（特殊・高額）'),
                value: 'register',
                groupValue: printGroup,
                onChanged: (v) => setState(() => printGroup = v!),
              ),
            ],
          );
        },
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            final price = int.tryParse(priceCtrl.text) ?? 0;
             final menu = context.read<MenuData>(); // ← ★これを必ず入れる
            context.read<MenuData>().updateVariant(
              v,
              nameCtrl.text,
              price,
              printGroup: printGroup, // ★ 追加
            );
             menu.save(); 
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

}

// =========================
// 共通UI
// =========================

class _PlusRow extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _PlusRow({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add,
                size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableBadge extends StatelessWidget {
  final String text;
  const _TableBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chair, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
                fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}
