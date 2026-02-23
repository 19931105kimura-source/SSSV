import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'cart_state.dart';



const _serverBaseUrl = 'http://192.168.11.8:3000';






/// =======================
/// テーブルの時間情報
/// =======================
class TableTimerInfo {
  int remainingSeconds;
  bool autoExtend;
  String? startTime; // "23:23" 形式

  TableTimerInfo({
    required this.remainingSeconds,
    required this.autoExtend,
    this.startTime,
  });

  Map<String, dynamic> toJson() => {
        'remainingSeconds': remainingSeconds,
        'autoExtend': autoExtend,
        'startTime': startTime, // ★ 保存
      };

  static TableTimerInfo fromJson(Map<String, dynamic> j) => TableTimerInfo(
        remainingSeconds: (j['remainingSeconds'] ?? 0) as int,
        autoExtend: (j['autoExtend'] ?? false) as bool,
        startTime: j['startTime'] as String?, // ★ 復元
      );
}

/// =======================
/// 注文明細
/// =======================
class OrderLine {
  final String category;
  final String brand;
  final String label;
  final int price;
  final int qty;
  final String? lineId; // ★ RT用
  /// 課税・区分など（normal / agency / extension 等を入れている想定）
  final String? section;

  /// 追加：サブカテゴリ
  final String subCategory;

  /// 印刷するか
  final bool shouldPrint;

  /// 印刷先グループ kitchen / register など
  final String printGroup;

  OrderLine({
    this.lineId, // ★ 追加
    required this.category,
    required this.brand,
    required this.label,
    required this.price,
    required this.qty,
    this.section,
    this.subCategory = '',
    this.shouldPrint = true,
    this.printGroup = 'kitchen',
  });

 Map<String, dynamic> toServerItem() {
  final trimmedLabel = label.trim();
  final displayName = trimmedLabel.isNotEmpty ? trimmedLabel : brand;
  final displayLabel = trimmedLabel.isNotEmpty ? trimmedLabel : brand;
  return {
    'name': displayName,    // ★ Node 側で使う表示名
    'label': displayLabel,  // 互換用（残してOK）
    'brand': brand,
    'category': category,
    'section': section,
    'subCategory': subCategory,
    'price': price,
    'qty': qty,
    'printGroup': printGroup, // ★ kitchen / register
  };
}


 OrderLine copyWith({int? qty, String? lineId}) => OrderLine(
        lineId: lineId ?? this.lineId,
        category: category,
        brand: brand,
        label: label,
        price: price,
        qty: qty ?? this.qty,
        section: section,
        subCategory: subCategory,
        shouldPrint: shouldPrint,
        printGroup: printGroup,
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'brand': brand,
        'label': label,
        'price': price,
        'qty': qty,
        'section': section,
        'subCategory': subCategory,
        'shouldPrint': shouldPrint,
        'printGroup': printGroup,
      };

 static OrderLine fromJson(Map<String, dynamic> j) => OrderLine(
        lineId: j['lineId'] as String?,
        category: (j['category'] ?? '') as String,
        brand: (j['brand'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        price: (j['price'] ?? 0) as int,
        qty: (j['qty'] ?? 0) as int,
        section: j['section'] as String?,
        subCategory: (j['subCategory'] ?? '') as String,
        shouldPrint: (j['shouldPrint'] ?? true) as bool,
        printGroup: (j['printGroup'] ?? 'kitchen') as String,
      );
}

/// =======================
/// 注文
/// =======================
class Order {
  final String id;
  String table;
  final DateTime createdAt;
  final List<OrderLine> lines;

  Order({
    required this.id,
    required this.table,
    required this.createdAt,
    required this.lines,
  });

  int get total => lines.fold(0, (sum, l) => sum + l.price * l.qty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'createdAt': createdAt.toIso8601String(),
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  static Order fromJson(Map<String, dynamic> j) => Order(
        id: (j['id'] ?? '') as String,
        table: (j['table'] ?? '') as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        lines: (j['lines'] as List)
            .map((e) => OrderLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// =======================
/// OrderState（完成版）
/// =======================

class OrderState extends ChangeNotifier {

  String? _lastSubmitError;
  int? _lastSubmitStatusCode;

  String? get lastSubmitError => _lastSubmitError;
  int? get lastSubmitStatusCode => _lastSubmitStatusCode;
String buildSubmitErrorMessageJa() {
    switch (_lastSubmitError) {
      case 'resync_required':
        return '同期中のため注文できません。数秒待って再試行してください。';
      case 'table_not_ordering':
        return 'この席は現在注文受付中ではありません。';
      case 'cart_empty':
        return 'カートが空のため注文できません。';
      case 'invalid_qty':
        return '数量が不正なため注文できません。';
      case 'server_rejected':
        final code = _lastSubmitStatusCode;
        if (code != null) {
          return '注文がサーバーで受理されませんでした（HTTP $code）。';
        }
        return '注文がサーバーで受理されませんでした。';
      case 'network_or_exception':
        return '通信に失敗しました。通信状態を確認して再試行してください。';
      default:
        return '注文を確定できませんでした。通信状態を確認して再試行してください。';
    }
  }
  bool _needsResync = true;
  DateTime? _lastSyncedAt;

  bool get canSubmitOrders => !_needsResync;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  void markNeedsResync() {
    if (_needsResync) return;
    _needsResync = true;
    notifyListeners();
  }


 /// ===================
/// ★ RT 正本：この席は注文できるか
/// ===================
bool canOrderTable(String table) {
  if (_needsResync) return false;
  // Realtime の status が最優先
  final status = realtimeTableStatus[table];
  if (status != null) {
    return status == 'ordering';
  }

  // fallback（RT 未接続時など）
  return _activeTables.contains(table);
}

  bool isRealtimeOrderId(String orderId) {
  return orderId.startsWith('rt_');
}
 // ★ Realtime：テーブルの状態（ordering / closed）
Map<String, String> realtimeTableStatus = {};

  Timer? _globalTimer;


  static const _keyOrders = 'orders_v1';
  static const _keyActive = 'active_tables_v1';

  // ★ 追加：タイマー永続化キー（外部APIに影響しない）
  static const _keyTimers = 'table_timers_v1';

  final List<Order> _orders = [];
  final Set<String> _activeTables = {};

  // ===============================
// Realtime snapshot 反映（Owner用）
// ===============================
  void applyRealtimeSnapshot(Map<String, dynamic> payload) {
  _needsResync = false;
  _lastSyncedAt = DateTime.now();
  // ★ 追加：テーブル状態を保存
  realtimeTables =
      Map<String, dynamic>.from(payload['tables'] ?? {});
  // ★ 席の状態を RT から反映
realtimeTableStatus.clear();

final tables = payload['tables'];
if (tables is Map) {
  tables.forEach((tableId, v) {
    if (v is Map && v['status'] is String) {
      realtimeTableStatus[tableId] = v['status'];
    }
  });
}

  // ★ ① RTデータを state に保存
  realtimeOrdersByTable =
      Map<String, dynamic>.from(payload['ordersByTable'] ?? {});
  realtimeOrderItems =
      Map<String, dynamic>.from(payload['orderItems'] ?? {});
  // ★ RT status → activeTables 同期
final tableMap =
    Map<String, dynamic>.from(payload['tables'] ?? {});
_activeTables.clear();

tableMap.forEach((tableId, data) {
  if (data is Map && data['status'] == 'ordering') {
    _activeTables.add(tableId.toString());
  }
});


  // ★ ② RTを正本として orders を組み直す
  final List<Order> newOrders = [];

  realtimeOrdersByTable.forEach((table, orderIds) {
    if (orderIds is! List) return;

    final List<OrderLine> lines = [];

    for (final orderId in orderIds) {
      final rawLines = realtimeOrderItems[orderId];
      if (rawLines is! List) continue;

      for (final raw in rawLines) {
        if (raw is Map<String, dynamic>) {
          lines.add(OrderLine.fromJson(raw));
        }
      }
    }

    if (lines.isEmpty) return;

    newOrders.add(
      Order(
        id: 'rt_$table',
        table: table,
        createdAt: DateTime.now(),
        lines: lines,
      ),
    );
  });

  _orders
    ..clear()
    ..addAll(newOrders);

  notifyListeners();
}



  // ===================
// ★ Realtime 注文データ（WebSocket）
// ===================
Map<String, dynamic> realtimeOrdersByTable = {};
Map<String, dynamic> realtimeOrderItems = {};
// ★ Realtime：テーブル状態（status の正本）
Map<String, dynamic> realtimeTables = {};

  /// テーブル一覧（永続化が必要なら別キーで保存を追加してください）
  final List<String> _tables = [
    'C1', 'C2', 'C3', 'C4',
    '1', '2', '3', '4', '5', '6', '7',
    '8', '9', '10', '11', '12', '13', '14',
    'VA', 'VB', 'VC',
  ];

  /// ★ テーブルごとのタイマー情報
  final Map<String, TableTimerInfo> tableTimers = {};

  OrderState() {
    load();
  }

   // ===================
// ★ Realtime 用：席ごとの注文明細数
// ===================
int realtimeItemCountOf(String table) {
  final orderIds = realtimeOrdersByTable[table];
  if (orderIds is! List) return 0;

  int count = 0;
  for (final orderId in orderIds) {
    final items = realtimeOrderItems[orderId];
    if (items is List) {
      count += items.length;
    }
  }
  return count;
}

  // ===================
  // getter（UI用）
  // ===================
  List<String> get tables => List.unmodifiable(_tables);

  List<Order> get orders => _orders.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool isActive(String table) {
  // ★ Realtime の status があればそれを正本にする
  final rt = realtimeTables[table];
  if (rt is Map && rt['status'] == 'ordering') {
    return true;
  }

  // ★ Realtime がまだ来ていない場合のみローカルを見る
  return _activeTables.contains(table);
}

  bool isActiveByRealtime(String table) {
  final t = realtimeTables[table];
  if (t is! Map<String, dynamic>) return false;
  return t['status'] == 'ordering';
}

  Order? orderOf(String table) {
    try {
      return _orders.firstWhere((o) => o.table == table);
    } catch (_) {
      return null;
    }
  }

  int totalOf(String table) => orderOf(table)?.total ?? 0;
  // ===================
// ★ 表示用：Realtime があればそれを優先する
// ===================
Order? orderForDisplay(String table) {
  // ① Realtime の注文があるか？
  final rt = _buildRealtimeOrder(table);
  if (rt != null) return rt;

  // ② なければ従来どおり（端末ローカル）
  return orderOf(table);
 }

// ===================
// ★ Realtime → Order に変換（表示専用）
// ===================
Order? _buildRealtimeOrder(String table) {
  // ordersByTable[table] が List じゃなければ Realtime なし扱い
  final orderIds = realtimeOrdersByTable[table];
  if (orderIds is! List) return null;

  // Realtime の item を集める（orderIdごとに items が入っている想定）
  final List<Map<String, dynamic>> rawItems = [];

  for (final orderId in orderIds) {
    final items = realtimeOrderItems[orderId];
    if (items is List) {
      for (final it in items) {
        if (it is Map) {
          rawItems.add(Map<String, dynamic>.from(it));
        }
      }
    }
  }

  // 何もなければ Realtime なし
  if (rawItems.isEmpty) return null;

  final List<OrderLine> lines = [];

  for (final it in rawItems) {
    final name = (it['name'] ?? '').toString().trim();
    final rawLabel = (it['label'] ?? '').toString().trim();
    final rawBrand = (it['brand'] ?? '').toString().trim();
    final rawCategory = (it['category'] ?? '').toString().trim();

    final label = name.isNotEmpty ? name : rawLabel;
    if (label.isEmpty) continue;

    final brand = rawBrand == 'RT' ? '' : rawBrand;
    final category = rawCategory == 'RT' ? '' : rawCategory;

    final price = _toInt(it['price']);
    final qty = _toInt(it['quantity'] ?? it['qty']);

    lines.add(
      OrderLine(
        lineId: it['lineId'] as String?, // ★ 追加
       category: category,
        brand: brand,
        label: label,
        price: price,
        qty: qty <= 0 ? 1 : qty,
         section: (it['section'] ?? 'RT').toString(),
        subCategory: (it['subCategory'] ?? '').toString(),
        shouldPrint: false,
        printGroup: (it['printGroup'] ?? 'kitchen').toString(),
      ),
    );
  }

  if (lines.isEmpty) return null;

 return Order(
    id: 'rt_$table',
    table: table,
    createdAt: DateTime.now(),
    lines: lines,
  );
}

  /// 表示用：同一商品を合算して返す
  List<OrderLine> aggregateLinesForDisplay(List<OrderLine> lines) {
    final Map<String, OrderLine> aggregated = {};

    for (final line in lines) {
      final label = line.label.trim();
      final brand = line.brand.trim();
      final displayName = label.isNotEmpty
          ? (brand.isNotEmpty ? '$brand $label' : label)
          : brand;
      final key = '${displayName.toLowerCase()}|${line.price}';
      if (!aggregated.containsKey(key)) {
        aggregated[key] = line.copyWith();
      } else {
        final cur = aggregated[key]!;
        aggregated[key] = cur.copyWith(qty: cur.qty + line.qty);
      }
    }

    return aggregated.values.toList();
  }

  bool _isSameLine(OrderLine a, OrderLine b) {
    return a.category == b.category &&
        a.brand == b.brand &&
        a.label == b.label &&
        a.price == b.price &&
        a.subCategory == b.subCategory;
  }

  Future<void> removeAggregatedLine(String orderId, OrderLine line) async {
    final oIdx = _orders.indexWhere((o) => o.id == orderId);
    if (oIdx == -1) return;
    final order = _orders[oIdx];
    order.lines.removeWhere((l) => _isSameLine(l, line));
    await _save();
    notifyListeners();
  }

  Future<void> updateAggregatedLineQty(
    String orderId,
    OrderLine line,
    int qty,
  ) async {
    final oIdx = _orders.indexWhere((o) => o.id == orderId);
    if (oIdx == -1) return;
    final order = _orders[oIdx];
    final matches = order.lines.where((l) => _isSameLine(l, line)).toList();
    if (matches.isEmpty) return;

    if (qty <= 0) {
      order.lines.removeWhere((l) => _isSameLine(l, line));
    } else {
      final template = matches.first;
      order.lines.removeWhere((l) => _isSameLine(l, line));
      order.lines.add(template.copyWith(qty: qty));
    }

    await _save();
    notifyListeners();
  }

// int変換（nullや文字でも落ちないように）
int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

  // ===================
  // ★ タイマー関連
  // ===================
  TableTimerInfo? timerOf(String table) => tableTimers[table];
// ===================
// ★ 互換：開始時刻だけ更新（呼び出し側がこれを使っている）
// ===================
void setTableTimerStartTime({
  required String table,
  required String startTime,
}) {
  final info = tableTimers[table];
  if (info == null) {
    tableTimers[table] = TableTimerInfo(
      remainingSeconds: 0,
      autoExtend: false,
      startTime: startTime,
    );
  } else {
    info.startTime = startTime;
  }

  _saveTimersOnly();
  notifyListeners();
}

////////////////////////// ===================
///
///// ===================
// ★ 互換：時間の加減（＋ / − ボタン用）
// ===================
void adjustTableTimerMinutes({
  String? table,
  int minutes = 0,
}) {
  if (table == null || minutes == 0) return;

  final info = tableTimers[table];
  if (info == null) return;

  info.remainingSeconds += minutes * 60;

  if (info.remainingSeconds < 0) {
    info.remainingSeconds = 0;
  }

  _saveTimersOnly();
  notifyListeners();
}

// ===================
// ★ タイマー開始 / 更新（互換対応版）
// ===================
void startTableTimer({
  required String table,

  // ★ UI 側の呼び方違いを吸収する
  int? remainingSeconds,
  int? totalSeconds,

  required bool autoExtend,
  String? startTime,
}) {
  final prev = tableTimers[table];

  // どれが来ても秒数を決定
  final seconds =
      remainingSeconds ?? totalSeconds ?? prev?.remainingSeconds ?? 0;

  tableTimers[table] = TableTimerInfo(
    remainingSeconds: seconds < 0 ? 0 : seconds,
    autoExtend: autoExtend,
    startTime: startTime ?? prev?.startTime,
  );

  _ensureGlobalTimer();
  _saveTimersOnly();
  notifyListeners();
}


  void clearTableTimer(String table) {
    if (tableTimers.remove(table) != null) {
      _saveTimersOnly(); // ★ 消したら保存
      notifyListeners();
    }
  }

  void _moveTimerKeyIfNeeded(String from, String to) {
    final info = tableTimers.remove(from);
    if (info != null) {
      tableTimers[to] = info;
      _saveTimersOnly(); // ★ 移動したら保存
    }
  }

  // ===================
  // 永続化
  // ===================
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final s = prefs.getString(_keyOrders);
    if (s != null) {
      final list = (jsonDecode(s) as List)
          .map((e) => Order.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _orders
        ..clear()
        ..addAll(list);
    }

    final a = prefs.getStringList(_keyActive);
    if (a != null) {
      _activeTables
        ..clear()
        ..addAll(a);
    }

    // ★ タイマー復元（開始時刻・残り時間を保持）
    final t = prefs.getString(_keyTimers);
    if (t != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(t));
        tableTimers
          ..clear()
          ..addAll(
            map.map(
              (k, v) => MapEntry(
                k,
                TableTimerInfo.fromJson(Map<String, dynamic>.from(v as Map)),
              ),
            ),
          );
      } catch (_) {
        // 壊れててもアプリを止めない
      }
    }

    // ★ 復元後にグローバルタイマーを確実に動かす
    if (tableTimers.isNotEmpty) {
      _ensureGlobalTimer();
    }

    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyOrders,
      jsonEncode(_orders.map((o) => o.toJson()).toList()),
    );
    await prefs.setStringList(
      _keyActive,
      _activeTables.toList(),
    );

    // ★ タイマーも一緒に保存（外部に影響しない）
    await prefs.setString(
      _keyTimers,
      jsonEncode(tableTimers.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  // ★ タイマーだけ保存（startTableTimer/clearTableTimer等から呼ぶ）
  Future<void> _saveTimersOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyTimers,
      jsonEncode(tableTimers.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  // ===================
  // テーブル開始 / 終了
  // ===================
  Future<void> startTable(String table) async {
    // ★ これを追加（サーバーへ通知）
  await _startTableOnServer(table);
    _activeTables.add(table);

    if (orderOf(table) == null) {
      _orders.add(
        Order(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          table: table,
          createdAt: DateTime.now(),
          lines: [],
        ),
      );
    }

    await _save();
    notifyListeners();
  }
Future<void> _endTableOnServer(String table) async {
  try {
    final uri = Uri.parse('$_serverBaseUrl/api/rt/tables/$table/end');

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    if (res.statusCode != 200) {
      debugPrint('END TABLE FAILED ${res.statusCode}');
    }
  } catch (e) {
    debugPrint('END TABLE ERROR: $e');
  }
}

  Future<void> endTable(String table) async {
    // ★ 追加：サーバーへ終了通知
  await _endTableOnServer(table);
    _activeTables.remove(table);
    realtimeTableStatus[table] = 'closed';
    final rt = realtimeTables[table];
    if (rt is Map<String, dynamic>) {
      rt['status'] = 'closed';
      realtimeTables[table] = rt;
    }

    clearTableTimer(table); // ★ 時間も確実に消す
    await _save();
    notifyListeners();
  }

  // ===================
  // Cart → Order
  // ===================
Future<bool> addFromCart(
  CartState cart,
  String table,
) async {
  _lastSubmitError = null;
  _lastSubmitStatusCode = null;

  if (!canSubmitOrders) {
    _lastSubmitError = 'resync_required';
    return false;
  }

  if (!canOrderTable(table)) {
    // 初回注文などでテーブルがまだ ordering でない場合は、
    // 先に開始リクエストを送ってから注文を試みる。
    await _startTableOnServer(table);
    _activeTables.add(table);
    realtimeTableStatus[table] = 'ordering';

    final rt = realtimeTables[table];
    if (rt is Map<String, dynamic>) {
      rt['status'] = 'ordering';
      realtimeTables[table] = rt;
    }
  }

  if (!canOrderTable(table)) {
    _lastSubmitError = 'table_not_ordering';
    return false;
  }
  if (cart.items.isEmpty) {
    _lastSubmitError = 'cart_empty';
    return false;
  }


    var order = orderOf(table);
if (order == null) {
  order = Order(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    table: table,
    createdAt: DateTime.now(),
    lines: [],
  );
  _orders.add(order);
}


     final List<OrderLine> deltaLines = [];
    for (final item in cart.items) {
      deltaLines.add(
        OrderLine(
          category: item.category,
          brand: item.brand,
          label: item.label,
          price: item.price,
          qty: item.qty,
          section: 'フロア',
          subCategory: '',
          shouldPrint: true,
          printGroup: item.printGroup,
        ),
      );

      final idx = order.lines.indexWhere(
        (l) =>
            l.category == item.category &&
            l.brand == item.brand &&
            l.label == item.label &&
            l.price == item.price,
      );

      if (idx >= 0) {
        final cur = order.lines[idx];
        order.lines[idx] = cur.copyWith(qty: cur.qty + item.qty);
      } else {
        order.lines.add(
          OrderLine(
            category: item.category,
            brand: item.brand,
            label: item.label,
            price: item.price,
            qty: item.qty,
           section: 'フロア',
            subCategory: '',
            shouldPrint: true,
            printGroup: item.printGroup,
          ),
        );
      }
    }
      // ✅ ここを追加

    final sent = await sendOrderToServer(order, linesToSend: deltaLines);
  if (!sent) {
    return false;
  }

    cart.clear();
    await _save();
    notifyListeners();
    return true;
  }
 Future<void> _startTableOnServer(String table) async {
  try {
    final uri = Uri.parse('$_serverBaseUrl/api/rt/tables/$table/start');

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
    );


    if (res.statusCode != 200) {
      debugPrint('START TABLE FAILED ${res.statusCode}');
    }
  } catch (e) {
    debugPrint('START TABLE ERROR: $e');
  }
}

  Future<bool> _moveTableOnServer({
    required String from,
    required String to,
  }) async {
    final uri = Uri.parse('$_serverBaseUrl/api/rt/tables/move');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'from': from, 'to': to}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> _mergeTableOnServer({
    required String from,
    required String to,
  }) async {
    final uri = Uri.parse('$_serverBaseUrl/api/rt/tables/merge');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'from': from, 'to': to}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  // ===================
  // 注文明細操作
  // ===================
  Future<void> removeLine(
    String orderId,
    OrderLine line,
  ) async {
    final o = _orders.firstWhere((o) => o.id == orderId);
    o.lines.removeWhere(
      (l) =>
          l.category == line.category &&
          l.brand == line.brand &&
          l.label == line.label &&
          l.price == line.price,
    );
    await _save();
    notifyListeners();
  }

  // ===================
  // 数量変更（+ / - 用）
  // ===================
  Future<void> updateQty(
    String orderId,
    OrderLine line,
    int qty,
  ) async {
    final oIdx = _orders.indexWhere((o) => o.id == orderId);
    if (oIdx == -1) return;

    final o = _orders[oIdx];

    final idx = o.lines.indexWhere(
      (l) =>
          l.category == line.category &&
          l.brand == line.brand &&
          l.label == line.label &&
          l.price == line.price,
    );
    if (idx == -1) return;

    if (qty <= 0) {
      o.lines.removeAt(idx);
    } else {
      o.lines[idx] = o.lines[idx].copyWith(qty: qty);
    }

    await _save();
    notifyListeners();
  }

  // ===================
  // 会計 / 削除
  // ===================
  Future<void> completeOrder(String orderId) async {
    await _save();
    notifyListeners();
  }

  Future<void> removeOrder(String orderId) async {
    _orders.removeWhere((o) => o.id == orderId);
    await _save();
    notifyListeners();
  }

  // ===================
  // 管理画面：直接注文追加（同一商品はqty合算）
  // ===================
   Future<bool> addManual({
    required String table,
    required String category,
    required String brand,
    required String label,
    required int price,
    bool shouldPrint = true,
    String subCategory = '',
    int qty = 1,
    required String section,
   }) async {
 _lastSubmitError = null;
  _lastSubmitStatusCode = null;

  if (!canSubmitOrders) {
    _lastSubmitError = 'resync_required';
    return false;
  }

  if (!canOrderTable(table)) {
    _lastSubmitError = 'table_not_ordering';
    return false;
  }
   if (qty <= 0) {
    _lastSubmitError = 'invalid_qty';
    return false;
   }


    final order = orderOf(table);
    if (order == null) {
      final newOrder = Order(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        table: table,
        createdAt: DateTime.now(),
        lines: [],
      );
      _orders.add(newOrder);
    }

    final targetOrder = orderOf(table);
    if (targetOrder == null) {
      _lastSubmitError = 'table_not_ordering';
      return false;
    }

    final idx = targetOrder.lines.indexWhere(
      (l) =>
          l.category == category &&
          l.brand == brand &&
          l.label == label &&
          l.price == price,
    );

    late final OrderLine deltaLine;
    if (idx >= 0) {
      final cur = targetOrder.lines[idx];
      targetOrder.lines[idx] = cur.copyWith(qty: cur.qty + qty);
      deltaLine = OrderLine(
        category: category,
        brand: brand,
        label: label,
        price: price,
        qty: qty,
        section: section,
        subCategory: subCategory,
        shouldPrint: shouldPrint,
        printGroup: 'kitchen',
      );
    } else {
      deltaLine = OrderLine(
        category: category,
        brand: brand,
        label: label,
        price: price,
        qty: qty,
        section: section,
        subCategory: subCategory,
        shouldPrint: shouldPrint,
        printGroup: 'kitchen',
      );
      targetOrder.lines.add(deltaLine);
    }

    final sent = await sendOrderToServer(targetOrder, linesToSend: [deltaLine]);
    if (!sent) {
      return false;
    }
    await _save();
    notifyListeners();
    return true;
  }

  // ===================
  // 全消し（開発用 / リセット用）
  // ===================
  Future<void> clearAll() async {
    _orders.clear();
    _activeTables.clear();
    tableTimers.clear();
    await _save();
    notifyListeners();
  }

  // ===================
  // 席移動：注文を別テーブルへ移す
  // ===================
  Future<void> moveTable({
    required String from,
    required String to,
  }) async {
    if (from == to) return;

    final fromOrder = orderOf(from);
    if (fromOrder == null) return;

    // 移動先にすでに注文がある場合は不可（事故防止）
    final toOrder = orderOf(to);
    if (toOrder != null && toOrder.lines.isNotEmpty) return;

   // 既存の移動先注文（空注文など）があれば削除
    if (toOrder != null) {
      _orders.removeWhere((o) => o.table == to);
    }

    final moved = await _moveTableOnServer(from: from, to: to);
    if (!moved) return;

    fromOrder.table = to;

    _activeTables.remove(from);
    _activeTables.add(to);

    // ★ タイマーも移動
    _moveTimerKeyIfNeeded(from, to);

    await _save();
    notifyListeners();
  }

  // ===================
  // 席合算：from の注文を to に合算
  // ===================
  Future<void> mergeTables({
    required String from,
    required String to,
  }) async {
    if (from == to) return;

    final fromOrder = orderOf(from);
    final toOrder = orderOf(to);

    if (fromOrder == null || toOrder == null) return;
    if (fromOrder.lines.isEmpty) return;

    final merged = await _mergeTableOnServer(from: from, to: to);
    if (!merged) return;

    for (final line in fromOrder.lines) {
      final idx = toOrder.lines.indexWhere(
        (l) =>
            l.category == line.category &&
            l.brand == line.brand &&
            l.label == line.label &&
            l.price == line.price,
      );

      if (idx >= 0) {
        final cur = toOrder.lines[idx];
        toOrder.lines[idx] = cur.copyWith(qty: cur.qty + line.qty);
      } else {
        toOrder.lines.add(line);
      }
    }

    // from 側の注文を削除
    _orders.removeWhere((o) => o.table == from);

    _activeTables.remove(from);

    // ★ from のタイマーは消す（合算後は to だけ）
    clearTableTimer(from);

    await _save();
    notifyListeners();
  }

  // ===================
  // テーブルに注文があるか
  // ===================
  bool hasOrder(String table) {
    final o = orderOf(table);
    return o != null && o.lines.isNotEmpty;
  }

  // ===================
  // テーブル追加
  // ===================
  Future<void> addTable(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    if (_tables.contains(n)) return;

    _tables.add(n);
    notifyListeners();
  }

  // ===================
  // テーブル削除（注文が残ってたら削除禁止）
  // ===================
  Future<void> removeTable(String name) async {
    if (hasOrder(name)) return;

    _tables.remove(name);
    _activeTables.remove(name);
    clearTableTimer(name);

    _orders.removeWhere((o) => o.table == name && o.lines.isEmpty);

    await _save();
    notifyListeners();
  }

  // ===================
  // テーブル名変更
  // ===================
  Future<void> renameTable(String oldName, String newName) async {
    final nn = newName.trim();
    if (nn.isEmpty) return;
    if (_tables.contains(nn)) return;

    final idx = _tables.indexOf(oldName);
    if (idx == -1) return;

    _tables[idx] = nn;

    // 注文テーブル名も更新
    for (final o in _orders) {
      if (o.table == oldName) o.table = nn;
    }

    // active 状態も移し替え
    if (_activeTables.remove(oldName)) {
      _activeTables.add(nn);
    }

    // ★ タイマーも移し替え
    _moveTimerKeyIfNeeded(oldName, nn);

    await _save();
    notifyListeners();
  }

  // ===================
  // サーバー送信（必要なら呼び出し側で利用）
  // ===================
 String _nextRequestId() {
    const max = 1 << 32;
    debugPrint('REQID START max=$max');
    final n = Random().nextInt(max);
    final id = '${DateTime.now().microsecondsSinceEpoch}_$n';
    debugPrint('REQID OK id=$id');
    return id;
  }

  Future<bool> sendOrderToServer(
    Order order, {
    List<OrderLine>? linesToSend,
  }) async {
    debugPrint('SEND ORDER START'); // ← これを追加
    _lastSubmitStatusCode = null;
    try {
      if (!canSubmitOrders) {
        _lastSubmitError = 'resync_required';
        return false;
       }
      final uri = Uri.parse('$_serverBaseUrl/api/orders');
      final lines = linesToSend ?? order.lines;
      debugPrint('SEND ORDER PHASE 1 uri=$uri lines=${lines.length}');

      late final String requestId;
      try {
        requestId = _nextRequestId();
      } catch (e, st) {
        debugPrint('SEND ORDER FAIL PHASE=requestId error=$e');
        debugPrint('$st');
        rethrow;
      }

      late final List<Map<String, dynamic>> items;
      try {
        items = lines
            .where((l) => l.shouldPrint)
            .map((l) => l.toServerItem())
            .toList();
      } catch (e, st) {
        debugPrint('SEND ORDER FAIL PHASE=toServerItem error=$e');
        debugPrint('$st');
        rethrow;
      }

      final payload = {
        'requestId': requestId,
        'tableId': order.table,
        'orderedBy': order.table.startsWith('C') ? 'guest' : 'owner',
        'items': items,
      };

      late final String body;
      try {
        body = jsonEncode(payload);
      } catch (e, st) {
        debugPrint('SEND ORDER FAIL PHASE=jsonEncode error=$e');
        debugPrint('$st');
        rethrow;
      }

      debugPrint('REQ /api/orders payload=$body');

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      debugPrint('RES /api/orders status=${res.statusCode}');
      debugPrint('RES /api/orders body=${res.body}');

     if (res.statusCode != 200) {
        _lastSubmitError = 'server_rejected';
        _lastSubmitStatusCode = res.statusCode;
        throw Exception('order send failed');
      }
      _lastSubmitError = null;
      return true;
    } catch (e) {
  _lastSubmitError ??= 'network_or_exception';
  debugPrint('SEND ORDER ERROR: $e');
}
    return false;
  }

  // ★ ステップ④：グローバルタイマー起動
  void _ensureGlobalTimer() {
    _globalTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        bool changed = false;

        tableTimers.forEach((table, info) {
          if (!info.autoExtend && info.remainingSeconds > 0) {
            info.remainingSeconds--;
            changed = true;
          }
        });

        if (changed) {
          // ★ 減った秒数を保存（アプリ落ちても復元できる）
          _saveTimersOnly();
          notifyListeners();
        }
      },
    );
  }
}