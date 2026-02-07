import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  late final WebSocketChannel _channel;

  void connect(void Function(Map<String, dynamic>) onSnapshot) {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://192.168.11.8:3000'),
    );

   _channel.stream.listen((data) {
  final decoded = jsonDecode(data);

  if (decoded['type'] == 'snapshot') {
    onSnapshot(
      Map<String, dynamic>.from(decoded['payload']),
    );
  }
});

  }

  void dispose() {
    _channel.sink.close();
  }
}
