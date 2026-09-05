import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_telegram/core/crypto/crypto_service.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/network/p2p_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Public Connect REST API & Web Landing Page verification', () async {
    final crypto = CryptoService();
    await crypto.initialize();

    final server = P2pServer(
      requestedPort: 49001,
      deviceId: 'api-test-node-1',
      deviceName: 'Alice Public Node',
      cryptoService: crypto,
    );

    Peer? announcedPeer;
    server.onPeerAnnouncedViaApi = (peer) {
      announcedPeer = peer;
    };

    final port = await server.start();
    expect(port, equals(49001));

    final httpClient = HttpClient();

    try {
      // 1. Test Web Landing Page (GET /)
      final reqRoot = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/'));
      final resRoot = await reqRoot.close();
      expect(resRoot.statusCode, equals(HttpStatus.ok));
      expect(resRoot.headers.contentType?.mimeType, equals('text/html'));
      final htmlBody = await utf8.decodeStream(resRoot);
      expect(htmlBody, contains('Alice Public Node'));
      expect(htmlBody, contains('OZO P2P'));
      expect(htmlBody, contains('Open in OZO App'));
      expect(htmlBody, contains(server.safetyFingerprint));

      // 2. Test Node Info API (GET /api/info)
      final reqInfo = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/api/info'));
      final resInfo = await reqInfo.close();
      expect(resInfo.statusCode, equals(HttpStatus.ok));
      expect(resInfo.headers.contentType?.mimeType, equals('application/json'));
      final infoJson = jsonDecode(await utf8.decodeStream(resInfo)) as Map<String, dynamic>;
      expect(infoJson['app'], equals('OZO'));
      expect(infoJson['name'], equals('Alice Public Node'));
      expect(infoJson['status'], equals('online'));
      expect(infoJson['safetyFingerprint'], equals(server.safetyFingerprint));
      expect(infoJson['endpoints']['connect'], equals('/api/connect'));

      // 3. Test Connect Info (GET /api/connect)
      final reqConnect = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/api/connect'));
      final resConnect = await reqConnect.close();
      expect(resConnect.statusCode, equals(HttpStatus.ok));
      final connectJson = jsonDecode(await utf8.decodeStream(resConnect)) as Map<String, dynamic>;
      expect(connectJson['success'], isTrue);
      expect(connectJson['ozoUri'], startsWith('ozo://connect?'));
      expect(connectJson['wsUrl'], startsWith('ws://'));

      // 4. Test Health Endpoint (GET /api/health)
      final reqHealth = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/api/health'));
      final resHealth = await reqHealth.close();
      expect(resHealth.statusCode, equals(HttpStatus.ok));
      final healthJson = jsonDecode(await utf8.decodeStream(resHealth)) as Map<String, dynamic>;
      expect(healthJson['status'], equals('healthy'));
      expect(healthJson['app'], equals('OZO'));

      // 5. Test Remote Peer Announcement (POST /api/connect)
      final reqPost = await httpClient.postUrl(Uri.parse('http://127.0.0.1:$port/api/connect'));
      reqPost.headers.contentType = ContentType.json;
      reqPost.write(jsonEncode({
        'id': 'remote-client-bob',
        'name': 'Bob Web Client',
        'pubKey': 'MOCK_REMOTE_PUBKEY_123',
        'platform': 'web',
      }));
      final resPost = await reqPost.close();
      expect(resPost.statusCode, equals(HttpStatus.ok));
      final postJson = jsonDecode(await utf8.decodeStream(resPost)) as Map<String, dynamic>;
      expect(postJson['success'], isTrue);
      expect(postJson['hostId'], equals('api-test-node-1'));
      expect(postJson['wsUrl'], isNotEmpty);

      // Verify that callback received the registered peer
      expect(announcedPeer, isNotNull);
      expect(announcedPeer!.id, equals('remote-client-bob'));
      expect(announcedPeer!.name, equals('Bob Web Client'));
      expect(announcedPeer!.publicKey, equals('MOCK_REMOTE_PUBKEY_123'));
    } finally {
      httpClient.close(force: true);
      await server.stop();
    }
  });
}
