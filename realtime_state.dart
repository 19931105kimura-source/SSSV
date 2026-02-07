import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import 'order_state.dart';

class RealtimeState extends ChangeNotifier {
  final OrderState orderState;
  final WebSocketService _ws = WebSocketService();
  bool _connected = false;

  RealtimeState(this.orderState);
  Map<String, dynamic> _snapshot = {};

  Map<String, dynamic> get snapshot => _snapshot;
  Map<String, dynamic> tables = {};
  Map<String, dynamic> ordersByTable = {};
  Map<String, dynamic> orderItems = {};
  
   
  // ★ ここを復活：外部から呼んでもOKにする（エラー封じ）
  void applySnapshot(Map<String, dynamic> payload) {
    debugPrint('SNAPSHOT RECEIVED');
   
    tables = Map<String, dynamic>.from(payload['tables'] ?? {});
    ordersByTable = Map<String, dynamic>.from(payload['ordersByTable'] ?? {});
    orderItems = Map<String, dynamic>.from(payload['orderItems'] ?? {});

    // ★ UI本体へ反映
    orderState.applyRealtimeSnapshot(payload);

    notifyListeners();
  }

  void connect() {
    if (_connected) return;

    _ws.connect((payload) {
      applySnapshot(payload); // ★ ここで統一
    });

    _connected = true;
  }

  @override
  void dispose() {
    _ws.dispose();
    super.dispose();
  }
}
