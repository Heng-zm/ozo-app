import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lan_telegram/core/crypto/crypto_service.dart';
import 'package:lan_telegram/core/database/app_database.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/network/p2p_client.dart';
import 'package:lan_telegram/core/network/p2p_server.dart';
import 'package:lan_telegram/core/transfers/file_transfer_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('E2E Two-Device Connection, Public REST API, E2EE Chat, and Chunked File Transfer', () async {
    SharedPreferences.setMockInitialValues({});

    final tempDirAlice = await Directory.systemTemp.createTemp('e2e_alice_');
    final tempDirBob = await Directory.systemTemp.createTemp('e2e_bob_');
    final httpClient = HttpClient();

    // =========================================================================
    // 1. SPIN UP DEVICE A (ALICE)
    // =========================================================================
    final aliceCrypto = CryptoService();
    await aliceCrypto.initialize();
    final aliceDb = AppDatabase();
    await aliceDb.initialize(customDirectory: tempDirAlice);

    final aliceServer = P2pServer(
      requestedPort: 47001,
      deviceId: 'device-alice-001',
      deviceName: 'Alice Phone',
      cryptoService: aliceCrypto,
    );
    final alicePort = await aliceServer.start();
    expect(alicePort, equals(47001));

    final aliceClient = P2pClient(
      deviceId: 'device-alice-001',
      deviceName: 'Alice Phone',
      cryptoService: aliceCrypto,
    );
    final aliceTransferManager = FileTransferManager(
      server: aliceServer,
      client: aliceClient,
      database: aliceDb,
      customDownloadDirectory: tempDirAlice,
    );

    // =========================================================================
    // 2. SPIN UP DEVICE B (BOB)
    // =========================================================================
    final bobCrypto = CryptoService();
    await bobCrypto.initialize();
    final bobDb = AppDatabase();
    await bobDb.initialize(customDirectory: tempDirBob);

    final bobServer = P2pServer(
      requestedPort: 47002,
      deviceId: 'device-bob-002',
      deviceName: 'Bob Laptop',
      cryptoService: bobCrypto,
    );
    final bobPort = await bobServer.start();
    expect(bobPort, equals(47002));

    final bobClient = P2pClient(
      deviceId: 'device-bob-002',
      deviceName: 'Bob Laptop',
      cryptoService: bobCrypto,
    );
    final bobTransferManager = FileTransferManager(
      server: bobServer,
      client: bobClient,
      database: bobDb,
      customDownloadDirectory: tempDirBob,
    );

    try {
      // =======================================================================
      // 3. TEST PUBLIC REST API ENDPOINTS ON DEVICE A
      // =======================================================================
      // A. GET / (Web Landing Page)
      final reqWeb = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$alicePort/'));
      final resWeb = await reqWeb.close();
      expect(resWeb.statusCode, equals(HttpStatus.ok));
      expect(resWeb.headers.contentType?.mimeType, equals('text/html'));
      final webHtml = await utf8.decodeStream(resWeb);
      expect(webHtml, contains('Alice Phone'));
      expect(webHtml, contains('OZO P2P'));
      expect(webHtml, contains(aliceServer.safetyFingerprint));

      // B. GET /api/info (Node Information)
      final reqInfo = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$alicePort/api/info'));
      final resInfo = await reqInfo.close();
      expect(resInfo.statusCode, equals(HttpStatus.ok));
      final infoJson = jsonDecode(await utf8.decodeStream(resInfo)) as Map<String, dynamic>;
      expect(infoJson['app'], equals('OZO'));
      expect(infoJson['name'], equals('Alice Phone'));
      expect(infoJson['status'], equals('online'));
      expect(infoJson['pubKey'], equals(aliceCrypto.publicKeyBase64));
      expect(infoJson['safetyFingerprint'], equals(aliceServer.safetyFingerprint));

      // C. GET /api/health (Health Check)
      final reqHealth = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$alicePort/api/health'));
      final resHealth = await reqHealth.close();
      expect(resHealth.statusCode, equals(HttpStatus.ok));
      final healthJson = jsonDecode(await utf8.decodeStream(resHealth)) as Map<String, dynamic>;
      expect(healthJson['status'], equals('healthy'));

      // D. GET /api/connect (Connection Parameters)
      final reqConnect = await httpClient.getUrl(Uri.parse('http://127.0.0.1:$alicePort/api/connect'));
      final resConnect = await reqConnect.close();
      expect(resConnect.statusCode, equals(HttpStatus.ok));
      final connectJson = jsonDecode(await utf8.decodeStream(resConnect)) as Map<String, dynamic>;
      expect(connectJson['success'], isTrue);
      expect(connectJson['id'], equals('device-alice-001'));
      expect(connectJson['ozoUri'], contains('ozo://connect?'));

      // E. POST /api/connect (Device B registers itself with Device A via Public API)
      Peer? registeredPeerOnAlice;
      aliceServer.onPeerAnnouncedViaApi = (p) {
        registeredPeerOnAlice = p;
      };

      final reqPost = await httpClient.postUrl(Uri.parse('http://127.0.0.1:$alicePort/api/connect'));
      reqPost.headers.contentType = ContentType.json;
      reqPost.write(jsonEncode({
        'id': 'device-bob-002',
        'name': 'Bob Laptop',
        'pubKey': bobCrypto.publicKeyBase64,
        'platform': 'windows',
      }));
      final resPost = await reqPost.close();
      expect(resPost.statusCode, equals(HttpStatus.ok));
      final postJson = jsonDecode(await utf8.decodeStream(resPost)) as Map<String, dynamic>;
      expect(postJson['success'], isTrue);
      expect(postJson['hostId'], equals('device-alice-001'));
      expect(postJson['hostPubKey'], equals(aliceCrypto.publicKeyBase64));

      expect(registeredPeerOnAlice, isNotNull);
      expect(registeredPeerOnAlice!.id, equals('device-bob-002'));
      expect(registeredPeerOnAlice!.name, equals('Bob Laptop'));
      expect(registeredPeerOnAlice!.publicKey, equals(bobCrypto.publicKeyBase64));

      // =======================================================================
      // 4. TWO-WAY ENCRYPTED (E2EE) CHAT BETWEEN DEVICE A AND DEVICE B
      // =======================================================================
      final alicePeer = Peer(
        id: 'device-alice-001',
        name: 'Alice Phone',
        ip: '127.0.0.1',
        port: alicePort,
        publicKey: aliceCrypto.publicKeyBase64!,
        platform: 'android',
        lastSeen: DateTime.now(),
      );

      final bobPeer = Peer(
        id: 'device-bob-002',
        name: 'Bob Laptop',
        ip: '127.0.0.1',
        port: bobPort,
        publicKey: bobCrypto.publicKeyBase64!,
        platform: 'windows',
        lastSeen: DateTime.now(),
      );

      // Listeners for message reception on both sides
      final bobReceivedCompleter = Completer<ChatMessage>();
      bobServer.onMessageReceived = (msg) {
        bobReceivedCompleter.complete(msg);
      };

      final aliceReceivedCompleter = Completer<ChatMessage>();
      aliceServer.onMessageReceived = (msg) {
        aliceReceivedCompleter.complete(msg);
      };

      // Alice sends encrypted message to Bob
      final aliceMsg = ChatMessage(
        id: 'alice-msg-101',
        chatId: bobPeer.id,
        senderId: alicePeer.id,
        senderName: alicePeer.name,
        recipientId: bobPeer.id,
        content: 'Hey Bob! Testing E2EE P2P Chat between two devices 🚀',
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );

      final aliceSendSuccess = await aliceClient.sendMessage(
        peer: bobPeer,
        message: aliceMsg,
      );
      expect(aliceSendSuccess, isTrue);

      final msgAtBob = await bobReceivedCompleter.future.timeout(const Duration(seconds: 5));
      expect(msgAtBob.id, equals('alice-msg-101'));
      expect(msgAtBob.content, equals('Hey Bob! Testing E2EE P2P Chat between two devices 🚀'));
      expect(msgAtBob.senderId, equals(alicePeer.id));

      // Bob replies with an encrypted message to Alice
      final bobReply = ChatMessage(
        id: 'bob-msg-202',
        chatId: alicePeer.id,
        senderId: bobPeer.id,
        senderName: bobPeer.name,
        recipientId: alicePeer.id,
        content: 'Hi Alice! Message decrypted and verified securely. All systems nominal! ✅',
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );

      final bobSendSuccess = await bobClient.sendMessage(
        peer: alicePeer,
        message: bobReply,
      );
      expect(bobSendSuccess, isTrue);

      final msgAtAlice = await aliceReceivedCompleter.future.timeout(const Duration(seconds: 5));
      expect(msgAtAlice.id, equals('bob-msg-202'));
      expect(msgAtAlice.content, equals('Hi Alice! Message decrypted and verified securely. All systems nominal! ✅'));
      expect(msgAtAlice.senderId, equals(bobPeer.id));

      // =======================================================================
      // 5. CHUNKED FILE TRANSFER TEST WITH CRYPTOGRAPHIC INTEGRITY VERIFICATION
      // =======================================================================
      final testFileDir = await Directory.systemTemp.createTemp('file_transfer_test_');
      final sampleFile = File('${testFileDir.path}/confidential_blueprint.bin');

      // Create a 1 MB test file with pseudo-random deterministic byte pattern
      final sampleBytes = Uint8List.fromList(List.generate(1024 * 1024, (i) => (i * 31 + 17) % 256));
      await sampleFile.writeAsBytes(sampleBytes);
      final originalSha256 = (await sha256.bind(sampleFile.openRead()).first).toString();

      // Alice offers the file to Bob
      final transferId = await aliceTransferManager.offerFile(
        peer: bobPeer,
        file: sampleFile,
        messageId: 'msg-file-transfer-303',
        myPlatform: 'android',
      );
      expect(transferId, isNotNull);

      // Bob accepts file offer and starts downloading chunk-by-chunk via HTTP range
      final fileMetadata = FileMetadata(
        transferId: transferId!,
        fileName: 'confidential_blueprint.bin',
        fileSize: sampleBytes.length,
        sha256: originalSha256,
      );

      await bobTransferManager.acceptAndDownload(
        metadata: fileMetadata,
        sender: alicePeer,
        messageId: 'msg-file-transfer-303',
      );

      // Await transfer completion on Bob's side
      int waitElapsedMs = 0;
      while (waitElapsedMs < 7000) {
        final status = bobTransferManager.getTransfer(transferId);
        if (status != null && status.status == TransferStatus.completed) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        waitElapsedMs += 100;
      }

      final bobTransferInfo = bobTransferManager.getTransfer(transferId);
      expect(bobTransferInfo, isNotNull);
      expect(bobTransferInfo!.status, equals(TransferStatus.completed));
      expect(bobTransferInfo.bytesTransferred, equals(sampleBytes.length));

      // Verify received file on Bob's disk and check SHA-256 hash match
      final bobFile = File(bobTransferInfo.localPath);
      expect(await bobFile.exists(), isTrue);
      expect(await bobFile.length(), equals(sampleBytes.length));

      final downloadedSha256 = (await sha256.bind(bobFile.openRead()).first).toString();
      expect(downloadedSha256, equals(originalSha256));

      // Cleanup temp test directory
      try {
        await testFileDir.delete(recursive: true);
      } catch (_) {}
    } finally {
      httpClient.close(force: true);
      await aliceDb.close();
      await bobDb.close();
      await aliceServer.stop();
      await bobServer.stop();
      aliceClient.close();
      bobClient.close();
      aliceTransferManager.dispose();
      bobTransferManager.dispose();
      try {
        await tempDirAlice.delete(recursive: true);
      } catch (_) {}
      try {
        await tempDirBob.delete(recursive: true);
      } catch (_) {}
    }
  });
}
