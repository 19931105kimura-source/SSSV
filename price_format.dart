import 'package:intl/intl.dart';

String formatYen(num value) {
  return '¥${NumberFormat('#,###').format(value)}';
}
