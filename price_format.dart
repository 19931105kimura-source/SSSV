import 'package:intl/intl.dart';

int truncateToTenYen(num value) {
  return (value ~/ 10) * 10;
}

String formatYen(num value) {
  return '¥${NumberFormat('#,###').format(value)}';
}

String formatYenTruncatedToTen(num value) {
  return formatYen(truncateToTenYen(value));
}