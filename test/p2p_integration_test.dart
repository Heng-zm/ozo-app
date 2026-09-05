import 'dart:async';
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

  test('Full P2P E2EE Messaging and Chunked File Transfer between Peer A and Peer B', () async {
    SharedPreferences.setMockInitialValues({});

    final tempDirAlice = await Directory.systemTemp.createTemp('alice_db');
    final tempDirBob = await Directory.systemTemp.createTemp('bob_db');

    // 1. Initialize Peer A (Alice)
    final aliceCrypto = CryptoService();
    await aliceCrypto.initialize();
    final aliceDb = AppDatabase();
    await aliceDb.initialize(customDirectory: tempDirAlice);

    final aliceServer = P2pServer(
      requestedPort: 48001,
      deviceId: 'alice-id',
      deviceName: 'Alice PC',
      cryptoService: aliceCrypto,
    );
    final alicePort = await aliceServer.start();
    expect(alicePort, equals(48001));

    final aliceClient = P2pClient(
      deviceId: 'alice-id',
      deviceName: 'Alice PC',
      cryptoService: aliceCrypto,
    );
    final aliceTransferManager = FileTransferManager(
      server: aliceServer,
      client: aliceClient,
      database: aliceDb,
      customDownloadDirectory: tempDirAlice,
    );

    // 2. Initialize Peer B (Bob)
    final bobDb = AppDatabase();
    await bobDb.initialize(customDirectory: tempDirBob);

    final bobServer = P2pServer(
      requestedPort: 48002,
      deviceId: 'bob-id',
      deviceName: 'Bob Surface',
      cryptoService: aliceCrypto, // Simulates Bob crypto using same ECDH algorithm
    );
    final bobPort = await bobServer.start();
    expect(bobPort, equals(48002));

    final bobClient = P2pClient(
      deviceId: 'bob-id',
      deviceName: 'Bob Surface',
      cryptoService: aliceCrypto,
    );
    final bobTransferManager = FileTransferManager(
      server: bobServer,
      client: bobClient,
      database: bobDb,
      customDownloadDirectory: tempDirBob,
    );

    // 3. Setup message listener on Bob's server
    final completerMsg = Completer<ChatMessage>();
    bobServer.onMessageReceived = (msg) {
      completerMsg.complete(msg);
    };

    // 4. Alice sends an E2EE message to Bob
    final bobPeer = Peer(
      id: 'bob-id',
      name: 'Bob Surface',
      ip: '127.0.0.1',
      port: bobPort,
      publicKey: aliceCrypto.publicKeyBase64!,
      platform: 'windows',
      lastSeen: DateTime.now(),
    );

    final sentMsg = ChatMessage(
      id: 'msg-test-1',
      chatId: bobPeer.id,
      senderId: 'alice-id',
      senderName: 'Alice PC',
      recipientId: bobPeer.id,
      content: 'Secret P2P Message over LAN!',
      timestamp: DateTime.now(),
    );

    final sendSuccess = await aliceClient.sendMessage(
      peer: bobPeer,
      message: sentMsg,
    );
    expect(sendSuccess, isTrue);

    // Wait for Bob to receive and decrypt
    final receivedMsg = await completerMsg.future.timeout(const Duration(seconds: 5));
    expect(receivedMsg.content, equals('Secret P2P Message over LAN!'));
    expect(receivedMsg.senderId, equals('alice-id'));

    // 5. Test File Transfer from Alice to Bob
    final tempDir = await Directory.systemTemp.createTemp('lan_p2p_e2e');
    final dummyFile = File('${tempDir.path}/test_image.png');
    // Create 1 MB file
    final fileBytes = Uint8List.fromList(List.generate(1024 * 1024, (i) => (i * 7) % 256));
    await dummyFile.writeAsBytes(fileBytes);
    final expectedHash = (await sha256.bind(dummyFile.openRead()).first).toString();

    final transferId = await aliceTransferManager.offerFile(
      peer: bobPeer,
      file: dummyFile,
      messageId: 'msg-file-1',
      myPlatform: 'windows',
    );
    expect(transferId, isNotNull);

    // Bob accepts and downloads from Alice's HTTP range endpoint
    final alicePeer = Peer(
      id: 'alice-id',
      name: 'Alice PC',
      ip: '127.0.0.1',
      port: alicePort,
      publicKey: aliceCrypto.publicKeyBase64!,
      platform: 'windows',
      lastSeen: DateTime.now(),
    );

    final fileMeta = FileMetadata(
      transferId: transferId!,
      fileName: 'test_image.png',
      fileSize: fileBytes.length,
      sha256: expectedHash,
    );

    await bobTransferManager.acceptAndDownload(
      metadata: fileMeta,
      sender: alicePeer,
      messageId: 'msg-file-1',
    );

    // Wait for transfer to complete
    int waitMs = 0;
    while (waitMs < 5000) {
      final info = bobTransferManager.getTransfer(transferId);
      if (info != null && info.status == TransferStatus.completed) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      waitMs += 100;
    }

    final transferInfo = bobTransferManager.getTransfer(transferId);
    expect(transferInfo?.status, equals(TransferStatus.completed));
    expect(transferInfo?.bytesTransferred, equals(fileBytes.length));

    // Verify downloaded file integrity on disk
    final downloadedFile = File(transferInfo!.localPath);
    expect(await downloadedFile.exists(), isTrue);
    final actualHash = (await sha256.bind(downloadedFile.openRead()).first).toString();
    expect(actualHash, equals(expectedHash));

    // Cleanup
    await tempDir.delete(recursive: true);
    await tempDirAlice.delete(recursive: true);
    await tempDirBob.delete(recursive: true);
    await aliceServer.stop();
    await bobServer.stop();
    aliceClient.close();
    bobClient.close();
    aliceTransferManager.dispose();
    bobTransferManager.dispose();
  });
}
