import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../crypto/crypto_service.dart';
import '../database/models.dart';

typedef MessageCallback = void Function(ChatMessage message);
typedef FileOfferCallback = void Function(FileMetadata file, Peer sender);
typedef DeliveryReceiptCallback = void Function(String messageId, MessageStatus status);
typedef TypingCallback = void Function(String peerId, bool isTyping);

/// Embedded HTTP and WebSocket server running locally on each peer
class P2pServer {
  final int requestedPort;
  final String deviceId;
  final String deviceName;
  final CryptoService cryptoService;

  HttpServer? _server;
  int _actualPort = 0;

  // Active WebSocket connections: peerId -> WebSocket
  final Map<String, WebSocket> _activeSockets = {};

  // Active files available for download: transferId -> File
  final Map<String, File> _sharedFiles = {};

  // Callbacks
  MessageCallback? onMessageReceived;
  FileOfferCallback? onFileOffered;
  DeliveryReceiptCallback? onDeliveryReceipt;
  TypingCallback? onTyping;

  int get port => _actualPort;

  P2pServer({
    required this.requestedPort,
    required this.deviceId,
    required this.deviceName,
    required this.cryptoService,
  });

  /// Starts the embedded HTTP & WebSocket server
  Future<int> start() async {
    await stop();

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        requestedPort,
      );
    } catch (_) {
      // If requested port is taken, bind to dynamic port
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
      );
    }

    _actualPort = _server!.port;
    _server!.listen(_handleHttpRequest);

    return _actualPort;
  }

  void registerSharedFile(String transferId, File file) {
    _sharedFiles[transferId] = file;
  }

  void unregisterSharedFile(String transferId) {
    _sharedFiles.remove(transferId);
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    // Add CORS headers for flexibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/ws') {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleWebSocket(socket, request.connectionInfo?.remoteAddress.address ?? '');
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      }
      return;
    }

    if (path == '/api/info') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'id': deviceId,
        'name': deviceName,
        'pubKey': cryptoService.publicKeyBase64,
        'proto': AppConstants.protocolVersion,
      }));
      await request.response.close();
      return;
    }

    // File download endpoint with HTTP Range support for chunked & resumable transfers
    if (path.startsWith('/api/file/download/')) {
      final transferId = path.replaceFirst('/api/file/download/', '');
      await _handleFileDownload(request, transferId);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> _handleFileDownload(HttpRequest request, String transferId) async {
    final file = _sharedFiles[transferId];
    if (file == null || !await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('File not found or transfer expired');
      await request.response.close();
      return;
    }

    final fileSize = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    int startByte = 0;
    int endByte = fileSize - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        startByte = int.tryParse(parts[0]) ?? 0;
      }
      if (parts.length > 1 && parts[1].isNotEmpty) {
        endByte = int.tryParse(parts[1]) ?? (fileSize - 1);
      }

      if (startByte >= fileSize || endByte >= fileSize || startByte > endByte) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileSize');
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $startByte-$endByte/$fileSize');
    } else {
      request.response.statusCode = HttpStatus.ok;
    }

    final contentLength = endByte - startByte + 1;
    request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());
    request.response.headers.contentType = ContentType.binary;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    try {
      final raf = await file.open(mode: FileMode.read);
      await raf.setPosition(startByte);

      int bytesRemaining = contentLength;
      const bufferSize = 64 * 1024; // 64 KB buffer

      while (bytesRemaining > 0) {
        final toRead = bytesRemaining < bufferSize ? bytesRemaining : bufferSize;
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;

        request.response.add(chunk);
        await request.response.flush();
        bytesRemaining -= chunk.length;
      }

      await raf.close();
    } catch (e) {
      if (kDebugMode) print('Error streaming file: $e');
    } finally {
      await request.response.close();
    }
  }

  void _handleWebSocket(WebSocket socket, String remoteIp) {
    String? peerId;

    socket.listen(
      (data) async {
        try {
          final text = data is String ? data : utf8.decode(data as List<int>);
          final msg = jsonDecode(text) as Map<String, dynamic>;

          final type = msg['type'] as String?;
          final senderId = msg['senderId'] as String?;

          if (senderId != null) {
            peerId = senderId;
            _activeSockets[senderId] = socket;
          }

          switch (type) {
            case 'MSG':
              await _handleIncomingChatMessage(msg, remoteIp);
              break;
            case 'FILE_OFFER':
              _handleIncomingFileOffer(msg, remoteIp);
              break;
            case 'ACK':
              final messageId = msg['messageId'] as String;
              final status = msg['status'] == 'read'
                  ? MessageStatus.read
                  : MessageStatus.delivered;
              onDeliveryReceipt?.call(messageId, status);
              break;
            case 'TYPING':
              final isTyping = msg['isTyping'] as bool? ?? false;
              if (senderId != null) {
                onTyping?.call(senderId, isTyping);
              }
              break;
          }
        } catch (e) {
          if (kDebugMode) print('WS parse error: $e');
        }
      },
      onDone: () {
        if (peerId != null) {
          _activeSockets.remove(peerId);
        }
      },
      onError: (err) {
        if (peerId != null) {
          _activeSockets.remove(peerId);
        }
      },
    );
  }

  Future<void> _handleIncomingChatMessage(Map<String, dynamic> msg, String remoteIp) async {
    final senderId = msg['senderId'] as String;
    final senderName = msg['senderName'] as String? ?? 'Peer';
    final senderPubKey = msg['senderPubKey'] as String;
    final encryptedData = msg['payload'] as Map<String, dynamic>;
    final messageId = msg['id'] as String;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['ts'] as int);

    // Decrypt E2EE payload
    String plaintext = '';
    try {
      plaintext = await cryptoService.decryptMessage(
        encryptedData: encryptedData,
        senderPublicKeyBase64: senderPubKey,
      );
    } catch (e) {
      plaintext = '[Decryption failed: unauthenticated message]';
    }

    final chatMsg = ChatMessage(
      id: messageId,
      chatId: senderId, // 1-on-1 chat
      senderId: senderId,
      senderName: senderName,
      recipientId: deviceId,
      content: plaintext,
      type: MessageType.text,
      timestamp: timestamp,
      status: MessageStatus.delivered,
    );

    onMessageReceived?.call(chatMsg);

    // Send ACK back over WebSocket
    final socket = _activeSockets[senderId];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({
        'type': 'ACK',
        'messageId': messageId,
        'status': 'delivered',
        'senderId': deviceId,
      }));
    }
  }

  void _handleIncomingFileOffer(Map<String, dynamic> msg, String remoteIp) {
    final senderId = msg['senderId'] as String;
    final senderName = msg['senderName'] as String? ?? 'Peer';
    final senderPort = msg['senderPort'] as int? ?? AppConstants.defaultP2pPort;
    final senderPubKey = msg['senderPubKey'] as String? ?? '';

    final fileMeta = FileMetadata(
      transferId: msg['transferId'] as String,
      fileName: msg['fileName'] as String,
      fileSize: msg['fileSize'] as int,
      sha256: msg['sha256'] as String? ?? '',
    );

    final sender = Peer(
      id: senderId,
      name: senderName,
      ip: remoteIp,
      port: senderPort,
      publicKey: senderPubKey,
      platform: msg['platform'] as String? ?? 'unknown',
      lastSeen: DateTime.now(),
    );

    onFileOffered?.call(fileMeta, sender);
  }

  Future<void> stop() async {
    for (final socket in _activeSockets.values) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _activeSockets.clear();
    _sharedFiles.clear();

    await _server?.close(force: true);
    _server = null;
    _actualPort = 0;
  }
}
