import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ---- data ----
import 'data/menu_data.dart';
import 'data/cast_data.dart';
import 'data/cast_drink_data.dart';
import 'data/other_item_data.dart';

// ---- state ----
import 'state/app_state.dart';
import 'state/cart_state.dart';
import 'state/order_state.dart';
import 'state/promo_state.dart';
import 'state/set_data.dart';
import 'state/realtime_state.dart';

// ---- pages ----
import 'pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 起動前ロード
  final menuData = MenuData();
  await menuData.load();

  final orderState = OrderState();
  await orderState.load();

  runApp(
    MultiProvider(
      providers: [
        // --- core ---
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => CartState()),
        ChangeNotifierProvider(create: (_) => PromoState()),
        ChangeNotifierProvider(create: (_) => SetData()),

        // --- master data ---
        ChangeNotifierProvider(create: (_) => CastData()),
        ChangeNotifierProvider(create: (_) => CastDrinkData()),
        ChangeNotifierProvider(create: (_) => OtherItemData()),
        ChangeNotifierProvider(create: (_) => menuData),

        // --- order / realtime ---
        ChangeNotifierProvider(create: (_) => orderState),
        ChangeNotifierProvider(
          create: (_) => RealtimeState(orderState),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LoginPage(),
    );
  }
}
