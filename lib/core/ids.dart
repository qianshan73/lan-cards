import 'dart:convert';
import 'dart:math';

/// Credentials never appear in discovery records or another player's view.
String newId([int bytes = 18]) {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(bytes, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}
