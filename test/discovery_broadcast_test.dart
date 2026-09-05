import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Subnet-directed broadcast address calculation', () {
    String computeDirectedBroadcast(String ip) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        return '${parts[0]}.${parts[1]}.${parts[2]}.255';
      }
      return '255.255.255.255';
    }

    expect(computeDirectedBroadcast('192.168.1.45'), equals('192.168.1.255'));
    expect(computeDirectedBroadcast('10.0.0.12'), equals('10.0.0.255'));
    expect(computeDirectedBroadcast('172.16.2.88'), equals('172.16.2.255'));
    expect(computeDirectedBroadcast('invalid'), equals('255.255.255.255'));
  });
}
