import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MenuData extends ChangeNotifier {
  int _saveToken = 0;

    // =========================
  // カテゴリ削除
  // =========================
  void removeCategory(String name) {
    items.removeWhere((i) => i['category'] == name);
    
    notifyListeners();
  }

  // =========================
// カテゴリ名 変更
// =========================
void renameCategory(String oldName, String newName) {
  final nn = newName.trim();
  if (nn.isEmpty) return;

  for (final item in items) {
    if (item['category'] == oldName) {
      item['category'] = nn;
    }
  }

  
  notifyListeners();
}

// =========================
// カテゴリ 並び替え
// =========================
void reorderCategories(int oldIndex, int newIndex) {
  final cats = categories.toList();

  if (newIndex > oldIndex) newIndex--;

  final moved = cats.removeAt(oldIndex);
  cats.insert(newIndex, moved);

  // 並び順に従って items を再構築
  final List<Map<String, dynamic>> reordered = [];
  for (final c in cats) {
    reordered.addAll(items.where((i) => i['category'] == c));
  }

  items = reordered;

  
  notifyListeners();
}

  // =========================
// 銘柄 並び替え
// =========================
void reorderBrands(String category, int oldIndex, int newIndex) {
  final list = items.where((i) => i['category'] == category).toList();
  if (newIndex > oldIndex) newIndex--;

  final item = list.removeAt(oldIndex);
  list.insert(newIndex, item);

  items.removeWhere((i) => i['category'] == category);
  items.addAll(list);

  
  notifyListeners();
}

// =========================
// 銘柄 名称変更
// =========================
void renameBrand(Map<String, dynamic> brand, String newName) {
  final nn = newName.trim();
  if (nn.isEmpty) return;

  brand['name'] = nn;
  
  notifyListeners();
}

// =========================
// 銘柄 削除
// =========================
void removeBrand(Map<String, dynamic> brand) {
  items.remove(brand);
  
  notifyListeners();
}

// =========================
// 種類 並び替え
// =========================
void reorderVariants(
  Map<String, dynamic> brand,
  int oldIndex,
  int newIndex,
) {
  final vs = brand['variants'] as List;
  if (newIndex > oldIndex) newIndex--;

  final v = vs.removeAt(oldIndex);
  vs.insert(newIndex, v);

  
  notifyListeners();
}

  // =========================
  // 初期データ（省略可・今まで通り）
  // =========================
  static final List<Map<String, dynamic>> _defaultItems = [
    {
      'type': 'normal',
      'category': '焼酎',
      'name': '鏡月',
      'variants': [
        {'label': '鏡月グリーン', 'price': 5000, 'printGroup': 'drink'},
        {'label': '鏡月プレミアム', 'price': 6000, 'printGroup': 'drink'},
      ],
    },
  ];

  List<Map<String, dynamic>> items = [];

  MenuData() {
    items = _deepCopy(_defaultItems);
    load();
  }

  // =========================
  // サーバー保存
  // =========================
  Future<void> save() async {
  debugPrint('=== SAVE CALLED ===');

  try {
    final uri = Uri.parse('http://192.168.11.8:3000/api/menu');

    final body = {
      'items': buildServerMenuItems(),
    };

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      debugPrint('Menu save failed: ${res.statusCode}');
      return;
    }

    debugPrint('Menu saved to server');
    // ★ ここでは load() しない
  } catch (e) {
    debugPrint('Menu save exception: $e');
  }
}



  // =========================
  // サーバー読込
  // =========================
  Future<void> load() async {
  try {
    final uri = Uri.parse('http://192.168.11.8:3000/api/menu');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      debugPrint('Menu load failed: ${res.statusCode}');
      return;
    }

    final List<dynamic> data = jsonDecode(res.body);

    final Map<String, Map<String, dynamic>> grouped = {};

    for (final e in data) {
      final m = Map<String, dynamic>.from(e);

      final String category = m['category'] ?? '';
      final String name = m['name'] ?? '';
      final String type = m['type'] ?? 'normal';

      final String key = '$category::$name';

      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'type': type,
          'category': category,
          'name': name,
          'variants': <Map<String, dynamic>>[],
        };
      }

      grouped[key]!['variants'].add({
        'label': m['variantLabel'] ?? '',
        'price': m['price'],
        'printGroup': m['printTarget'],
      });
    }

    items = grouped.values.toList();

    debugPrint('MENU ITEMS: $items');
    notifyListeners();
  } catch (e, st) {
    debugPrint('Menu load exception: $e');
    debugPrint('$st');
  }
}


  // =========================
  // UI操作（今まで通り）
  // =========================
  List<String> get categories =>
      items.map((e) => e['category'] as String).toSet().toList();

 void addCategory(String name) {
  if (name.trim().isEmpty) return;

  items.add({
    'type': 'normal',
    'category': name,
    'name': name, // 仮で同じ名前を銘柄名にする
    'variants': [
      {
        'label': name, // 仮の種類
        'price': 0,
        'printGroup': 'none',
      }
    ],
  });

  
  notifyListeners();
}



  void addBrand(String category, String name, {String type = 'normal'}) {
  if (name.trim().isEmpty) return;

  items.add({
    'type': type,
    'category': category,
    'name': name,
    'variants': [
      {
        'label': name,      // 仮の種類を1つ入れる
        'price': 0,
        'printGroup': 'none',
      }
    ],
  });

 
  notifyListeners();
}


  void addVariant(
    Map<String, dynamic> brand,
    String label,
    int price, {
    String printGroup = 'none',
  }) {
    brand['variants'].add({
      'label': label,
      'price': price,
      'printGroup': printGroup,
    });
    
    notifyListeners();
  }

  void updateVariant(
    Map<String, dynamic> v,
    String label,
    int price, {
    String? printGroup,
  }) {
    v['label'] = label;
    v['price'] = price;
    if (printGroup != null) v['printGroup'] = printGroup;
  
    notifyListeners();
  }

  void removeVariant(Map<String, dynamic> brand, Map<String, dynamic> variant) {
    (brand['variants'] as List).remove(variant);
    
    notifyListeners();
  }

  // =========================
  // サーバー送信用変換（最重要）
  // =========================
  List<Map<String, dynamic>> buildServerMenuItems() {
    final List<Map<String, dynamic>> result = [];
    int seq = 1;

    for (final item in items) {
      final String type = item['type'] ?? 'normal';
      final String category = item['category'] ?? '';
      final String name = item['name'] ?? '';
      final List variants = item['variants'] ?? [];

      for (final v in variants) {
        result.add({
          'productId': 'p_${seq++}',
          'name': name,
          'variantLabel': v['label'] ?? '',
          'type': type,
          'price': v['price'] ?? 0,
          'category': category,
          'printTarget': v['printGroup'] ?? 'none',
          'isActive': true,
        });
      }
    }
    return result;
  }

  // =========================
  // 内部ユーティリティ
  // =========================
  static List<Map<String, dynamic>> _deepCopy(
    List<Map<String, dynamic>> src,
  ) =>
      src.map(_deepCopyItem).toList();

  static Map<String, dynamic> _deepCopyItem(Map<String, dynamic> src) {
    final v = (src['variants'] as List?) ?? [];
    return {
      'type': src['type'],
      'category': src['category'],
      'name': src['name'],
      'variants': v.map((x) => Map<String, dynamic>.from(x)).toList(),
    };
  }
}
