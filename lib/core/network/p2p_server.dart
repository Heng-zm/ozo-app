import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../crypto/crypto_service.dart';
import '../database/models.dart';

typedef MessageCallback = void Function(ChatMessage message);
typedef FileOfferCallback = void Function(FileMetadata file, Peer sender);
typedef DeliveryReceiptCallback = void Function(String messageId, MessageStatus status);
typedef TypingCallback = void Function(String peerId, bool isTyping);
typedef GroupInviteCallback = void Function(GroupChat group);
typedef GroupRelayCallback = void Function(ChatMessage message, String groupId);
typedef ReactionCallback = void Function(String messageId, String emoji, String senderId);
typedef DeleteMessageCallback = void Function(String messageId);
typedef CallSignalingCallback = void Function(CallSignaling signaling);

/// Embedded HTTP and WebSocket server running locally on each peer
class P2pServer {
  final int requestedPort;
  final String deviceId;
  final String deviceName;
  final CryptoService cryptoService;

  HttpServer? _server;
  int _actualPort = 0;
  DateTime? _startedAt;

  // Active WebSocket connections: peerId -> WebSocket
  final Map<String, WebSocket> _activeSockets = {};

  // Active files available for download: transferId -> File
  final Map<String, File> _sharedFiles = {};

  // Callbacks
  MessageCallback? onMessageReceived;
  FileOfferCallback? onFileOffered;
  DeliveryReceiptCallback? onDeliveryReceipt;
  TypingCallback? onTyping;
  GroupInviteCallback? onGroupInvite;
  GroupRelayCallback? onGroupMessage;
  void Function(String groupId, String newHostId, String newHostName, String? newBackupHostId, String? newBackupHostName)? onGroupMigrated;
  ReactionCallback? onReactionReceived;
  DeleteMessageCallback? onMessageDeleted;
  CallSignalingCallback? onCallSignaling;
  void Function(LinkedDevice device, String token)? onDevicePairRequest;
  void Function(Map<String, dynamic> backupData)? onBackupReceived;
  void Function(String chatId, String messageId)? onMessagePinned;
  void Function(String chatId)? onMessageUnpinned;
  void Function(Peer peer)? onPeerAnnouncedViaApi;

  int get port => _actualPort;

  DateTime? get startedAt => _startedAt;

  String get safetyFingerprint {
    final pk = cryptoService.publicKeyBase64 ?? '';
    if (pk.isEmpty) return '0000-0000';
    final digest = crypto.sha256.convert(utf8.encode(pk)).toString().toUpperCase();
    return '${digest.substring(0, 4)}-${digest.substring(4, 8)}';
  }

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
    _startedAt = DateTime.now();
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

    // WebSocket upgrade for real-time E2EE communication
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

    // Web Connect Landing Page
    if (path == '/' || path == '/connect') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_buildWebConnectHtml(request));
      await request.response.close();
      return;
    }

    // Node Information API
    if (path == '/api/info') {
      final uptime = _startedAt != null
          ? DateTime.now().difference(_startedAt!).inSeconds
          : 0;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'OZO',
        'version': '1.0.0',
        'protocol': AppConstants.protocolVersion,
        'id': deviceId,
        'name': deviceName,
        'pubKey': cryptoService.publicKeyBase64,
        'safetyFingerprint': safetyFingerprint,
        'status': 'online',
        'port': _actualPort,
        'uptimeSeconds': uptime,
        'endpoints': {
          'web': '/',
          'ws': '/ws',
          'info': '/api/info',
          'connect': '/api/connect',
          'health': '/api/health',
          'download': '/api/file/download/:transferId',
        }
      }));
      await request.response.close();
      return;
    }

    // Public Connect API (GET connection parameters / POST register peer)
    if (path == '/api/connect') {
      if (request.method == 'GET') {
        final hostHeader = request.headers.value('host') ?? '127.0.0.1';
        final isHttps = request.headers.value('x-forwarded-proto') == 'https';
        final hostOnly = hostHeader.split(':').first;
        final port = isHttps
            ? 443
            : (int.tryParse(hostHeader.contains(':') ? hostHeader.split(':').last : '') ?? _actualPort);

        final link = PeerConnectionLink(
          id: deviceId,
          name: deviceName,
          host: hostOnly,
          port: port,
          publicKey: cryptoService.publicKeyBase64 ?? '',
          platform: 'node',
          isSecure: isHttps,
        );

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'id': deviceId,
          'name': deviceName,
          'pubKey': cryptoService.publicKeyBase64,
          'safetyFingerprint': safetyFingerprint,
          'ozoUri': link.toUriString(),
          'wsUrl': '${isHttps ? 'wss' : 'ws'}://$hostHeader/ws',
          'host': hostOnly,
          'port': port,
          'isSecure': isHttps,
        }));
        await request.response.close();
        return;
      }

      if (request.method == 'POST') {
        try {
          final body = await utf8.decodeStream(request);
          final json = jsonDecode(body) as Map<String, dynamic>;
          final peerId = json['id'] as String?;
          final peerName = json['name'] as String? ?? 'Remote Web Peer';
          final peerPubKey = json['pubKey'] as String? ?? '';
          final peerPlatform = json['platform'] as String? ?? 'web';

          if (peerId == null || peerId.isEmpty || peerPubKey.isEmpty) {
            request.response.statusCode = HttpStatus.badRequest;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'success': false,
              'error': 'Missing required fields: id and pubKey',
            }));
            await request.response.close();
            return;
          }

          final remoteIp = request.headers.value('cf-connecting-ip') ??
              request.headers.value('x-forwarded-for')?.split(',').first.trim() ??
              request.connectionInfo?.remoteAddress.address ??
              '127.0.0.1';

          final peer = Peer(
            id: peerId,
            name: peerName,
            ip: remoteIp,
            port: request.connectionInfo?.remotePort ?? 45455,
            publicKey: peerPubKey,
            platform: peerPlatform,
            lastSeen: DateTime.now(),
            isRemote: true,
          );

          onPeerAnnouncedViaApi?.call(peer);

          final hostHeader = request.headers.value('host') ?? '127.0.0.1';
          final isHttps = request.headers.value('x-forwarded-proto') == 'https';

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'success': true,
            'hostId': deviceId,
            'hostName': deviceName,
            'hostPubKey': cryptoService.publicKeyBase64,
            'safetyFingerprint': safetyFingerprint,
            'wsUrl': '${isHttps ? 'wss' : 'ws'}://$hostHeader/ws',
            'message': 'Peer registered successfully. Connect to wsUrl for E2EE messaging.',
          }));
          await request.response.close();
          return;
        } catch (e) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'success': false, 'error': e.toString()}));
          await request.response.close();
          return;
        }
      }
    }

    // Health Check Endpoint
    if (path == '/api/health') {
      final uptime = _startedAt != null
          ? DateTime.now().difference(_startedAt!).inSeconds
          : 0;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'healthy',
        'app': 'OZO',
        'activeConnections': _activeSockets.length,
        'uptimeSeconds': uptime,
        'serverPort': _actualPort,
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
            case 'GROUP_INVITE':
              _handleIncomingGroupInvite(msg);
              break;
            case 'GROUP_MSG':
            case 'GROUP_RELAY':
              _handleIncomingGroupMessage(msg);
              break;
            case 'REACTION':
              final messageId = msg['messageId'] as String;
              final emoji = msg['emoji'] as String;
              if (senderId != null) {
                onReactionReceived?.call(messageId, emoji, senderId);
              }
              break;
            case 'DELETE_MSG':
              final messageId = msg['messageId'] as String;
              onMessageDeleted?.call(messageId);
              break;
            case 'CALL_OFFER':
            case 'CALL_ANSWER':
            case 'CALL_REJECT':
            case 'CALL_END':
              final signaling = CallSignaling.fromJson(msg);
              onCallSignaling?.call(signaling);
              break;
            case 'GROUP_MIGRATED':
              final groupId = msg['groupId'] as String;
              final newHostId = msg['newHostId'] as String;
              final newHostName = msg['newHostName'] as String? ?? 'New Host';
              final newBackupHostId = msg['newBackupHostId'] as String?;
              final newBackupHostName = msg['newBackupHostName'] as String?;
              onGroupMigrated?.call(groupId, newHostId, newHostName, newBackupHostId, newBackupHostName);
              break;
            case 'DEVICE_PAIR':
              final dev = LinkedDevice(
                id: msg['id'] as String,
                name: msg['name'] as String,
                platform: msg['platform'] as String? ?? 'unknown',
                publicKey: msg['pubKey'] as String? ?? '',
                linkedAt: DateTime.now(),
              );
              final token = msg['token'] as String? ?? '';
              onDevicePairRequest?.call(dev, token);
              break;
            case 'BACKUP_TRANSFER':
              final backup = msg['backup'] as Map<String, dynamic>;
              onBackupReceived?.call(backup);
              break;
            case 'MESSAGE_PIN':
              final chatId = msg['chatId'] as String;
              final messageId = msg['messageId'] as String;
              onMessagePinned?.call(chatId, messageId);
              break;
            case 'MESSAGE_UNPIN':
              final chatId = msg['chatId'] as String;
              onMessageUnpinned?.call(chatId);
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

    final msgTypeStr = msg['msgType'] as String?;
    final msgType = MessageType.values.firstWhere(
      (e) => e.name == msgTypeStr,
      orElse: () => MessageType.text,
    );
    final voiceDuration = (msg['voiceDuration'] as num?)?.toDouble();
    final amplitudes = (msg['amplitudes'] as List<dynamic>?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    final fileMeta = msg['fileMetadata'] != null
        ? FileMetadata.fromJson(msg['fileMetadata'] as Map<String, dynamic>)
        : null;

    final replyToId = msg['replyToId'] as String?;
    final replyToText = msg['replyToText'] as String?;
    final replyToSenderName = msg['replyToSenderName'] as String?;

    final chatMsg = ChatMessage(
      id: messageId,
      chatId: senderId, // 1-on-1 chat
      senderId: senderId,
      senderName: senderName,
      recipientId: deviceId,
      content: plaintext,
      type: msgType,
      timestamp: timestamp,
      status: MessageStatus.delivered,
      fileMetadata: fileMeta,
      voiceDurationSeconds: voiceDuration,
      waveformAmplitudes: amplitudes,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
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

  void _handleIncomingGroupInvite(Map<String, dynamic> msg) {
    try {
      final group = GroupChat.fromJson(msg['group'] as Map<String, dynamic>);
      onGroupInvite?.call(group);
    } catch (e) {
      if (kDebugMode) print('Failed to parse group invite: $e');
    }
  }

  void _handleIncomingGroupMessage(Map<String, dynamic> msg) {
    try {
      final groupId = msg['groupId'] as String;
      final messageId = msg['id'] as String;
      final senderId = msg['senderId'] as String;
      final senderName = msg['senderName'] as String? ?? 'Member';
      final content = msg['content'] as String? ?? '';
      final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch);

      final chatMsg = ChatMessage(
        id: messageId,
        chatId: groupId,
        senderId: senderId,
        senderName: senderName,
        recipientId: groupId,
        content: content,
        type: MessageType.text,
        timestamp: timestamp,
        status: MessageStatus.delivered,
        isGroup: true,
        groupId: groupId,
      );

      onGroupMessage?.call(chatMsg, groupId);
    } catch (e) {
      if (kDebugMode) print('Failed to parse group message: $e');
    }
  }

  /// Sends a read receipt for a message over active server socket
  void sendReadReceipt(String peerId, String messageId) {
    final socket = _activeSockets[peerId];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({
        'type': 'ACK',
        'messageId': messageId,
        'status': 'read',
        'senderId': deviceId,
      }));
    }
  }

  /// Sends typing indicator to peer over active server socket
  void sendTypingIndicator(String peerId, bool isTyping) {
    final socket = _activeSockets[peerId];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({
        'type': 'TYPING',
        'senderId': deviceId,
        'isTyping': isTyping,
      }));
    }
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

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _buildWebConnectHtml(HttpRequest request) {
    final hostHeader = request.headers.value('host') ?? '127.0.0.1';
    final isHttps = request.headers.value('x-forwarded-proto') == 'https';
    final hostOnly = hostHeader.split(':').first;
    final portNum = isHttps
        ? 443
        : (int.tryParse(hostHeader.contains(':') ? hostHeader.split(':').last : '') ?? _actualPort);

    final link = PeerConnectionLink(
      id: deviceId,
      name: deviceName,
      host: hostOnly,
      port: portNum,
      publicKey: cryptoService.publicKeyBase64 ?? '',
      platform: 'node',
      isSecure: isHttps,
    );

    final deepLink = link.toUriString();
    final webUrl = '${isHttps ? 'https' : 'http'}://$hostHeader';
    final wsUrl = '${isHttps ? 'wss' : 'ws'}://$hostHeader/ws';
    final safeName = _escapeHtml(deviceName);
    final safeId = _escapeHtml(deviceId);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OZO P2P • Connect to $safeName</title>
  <style>
    :root {
      --bg: #0e1621;
      --card: #17212b;
      --card-border: #242f3d;
      --primary: #2481cc;
      --primary-hover: #1e70b3;
      --text: #ffffff;
      --text-dim: #7f91a4;
      --green: #4fae4e;
      --accent: #64b5f6;
      --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    body {
      margin: 0;
      padding: 32px 16px;
      font-family: var(--font);
      background-color: var(--bg);
      color: var(--text);
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      box-sizing: border-box;
    }
    .container {
      width: 100%;
      max-width: 500px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--card-border);
      border-radius: 18px;
      padding: 24px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.35);
    }
    .header {
      text-align: center;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 8px;
    }
    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 12px;
      border-radius: 20px;
      background: rgba(79, 174, 78, 0.15);
      color: var(--green);
      font-size: 12px;
      font-weight: 600;
      margin-top: 4px;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--green);
      box-shadow: 0 0 8px var(--green);
    }
    h1 {
      margin: 8px 0 0 0;
      font-size: 24px;
      font-weight: 700;
    }
    .sub {
      color: var(--text-dim);
      font-size: 13px;
      margin: 0;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 10px 0;
      border-bottom: 1px solid rgba(255,255,255,0.06);
      font-size: 13px;
    }
    .info-row:last-child {
      border-bottom: none;
    }
    .info-label {
      color: var(--text-dim);
    }
    .info-val {
      font-weight: 600;
      font-family: monospace;
      color: var(--text);
    }
    .fingerprint {
      color: var(--accent);
      font-weight: 700;
      letter-spacing: 1px;
    }
    .qr-wrap {
      display: flex;
      justify-content: center;
      margin: 16px 0;
    }
    .qr-img {
      background: #ffffff;
      padding: 12px;
      border-radius: 14px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.25);
    }
    .btn {
      display: block;
      width: 100%;
      padding: 14px;
      border-radius: 12px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      text-align: center;
      text-decoration: none;
      box-sizing: border-box;
      border: none;
      transition: all 0.2s;
    }
    .btn-primary {
      background: var(--primary);
      color: #ffffff;
    }
    .btn-primary:hover {
      background: var(--primary-hover);
    }
    .btn-secondary {
      background: rgba(255,255,255,0.06);
      color: var(--text);
      border: 1px solid var(--card-border);
      margin-top: 8px;
    }
    .btn-secondary:hover {
      background: rgba(255,255,255,0.12);
    }
    .api-header {
      font-size: 14px;
      font-weight: 700;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .endpoint {
      background: rgba(0,0,0,0.25);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 8px 12px;
      font-family: monospace;
      font-size: 12px;
      margin-bottom: 6px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .method {
      color: var(--accent);
      font-weight: 700;
      margin-right: 6px;
    }
    .test-btn {
      background: rgba(36, 129, 204, 0.2);
      color: var(--accent);
      border: 1px solid rgba(36, 129, 204, 0.4);
      border-radius: 6px;
      padding: 3px 8px;
      font-size: 11px;
      cursor: pointer;
    }
    .test-btn:hover {
      background: rgba(36, 129, 204, 0.4);
    }
    pre {
      background: #090d13;
      padding: 12px;
      border-radius: 8px;
      font-size: 11px;
      overflow-x: auto;
      color: #9cdcfe;
      margin-top: 10px;
      border: 1px solid var(--card-border);
    }
    .toast {
      position: fixed;
      bottom: 24px;
      background: #2b5278;
      color: #fff;
      padding: 10px 20px;
      border-radius: 20px;
      font-size: 13px;
      display: none;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="card header">
      <div style="font-size: 38px;">⚡</div>
      <h1>$safeName</h1>
      <p class="sub">End-to-End Encrypted P2P Direct Connect</p>
      <div class="badge-status">
        <span class="dot"></span> Online &amp; Listening
      </div>
    </div>

    <div class="card">
      <div class="info-row">
        <span class="info-label">Peer Name</span>
        <span class="info-val">$safeName</span>
      </div>
      <div class="info-row">
        <span class="info-label">Device ID</span>
        <span class="info-val">${safeId.length > 12 ? '${safeId.substring(0, 12)}...' : safeId}</span>
      </div>
      <div class="info-row">
        <span class="info-label">Safety Fingerprint</span>
        <span class="info-val fingerprint">$safetyFingerprint</span>
      </div>
      <div class="info-row">
        <span class="info-label">Protocol</span>
        <span class="info-val">${AppConstants.protocolVersion}</span>
      </div>

      <div class="qr-wrap">
        <img class="qr-img" width="180" height="180" src="https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${Uri.encodeComponent(deepLink)}" alt="Connection QR Code" />
      </div>

      <a href="$deepLink" class="btn btn-primary">📱 Open in OZO App</a>
      <button onclick="copyText('$deepLink', 'OZO connection link copied to clipboard!')" class="btn btn-secondary">📋 Copy Deep Link</button>
      <button onclick="copyText('$webUrl', 'Public web link copied!')" class="btn btn-secondary">🌐 Copy Web Link</button>
    </div>

    <div class="card">
      <div class="api-header">
        <span>⚡ Public REST &amp; WebSocket API</span>
        <span style="font-size: 11px; color: var(--text-dim);">Zero-Auth Local/Public</span>
      </div>
      <div class="endpoint">
        <span><span class="method">GET</span> /api/info</span>
        <button class="test-btn" onclick="callApi('/api/info')">Test Live</button>
      </div>
      <div class="endpoint">
        <span><span class="method">GET</span> /api/connect</span>
        <button class="test-btn" onclick="callApi('/api/connect')">Test Live</button>
      </div>
      <div class="endpoint">
        <span><span class="method">GET</span> /api/health</span>
        <button class="test-btn" onclick="callApi('/api/health')">Test Live</button>
      </div>
      <div class="endpoint">
        <span><span class="method">POST</span> /api/connect</span>
        <span style="font-size: 11px; color: var(--text-dim);">Announce &amp; Register</span>
      </div>
      <div class="endpoint">
        <span><span class="method">WS</span> $wsUrl</span>
        <span style="font-size: 11px; color: var(--text-dim);">E2EE Chat Socket</span>
      </div>
      <pre id="api-output" style="display:none;"></pre>
    </div>
  </div>

  <div id="toast" class="toast"></div>

  <script>
    async function callApi(path) {
      const out = document.getElementById('api-output');
      out.style.display = 'block';
      out.textContent = 'Fetching ' + path + '...';
      try {
        const res = await fetch(path);
        const data = await res.json();
        out.textContent = JSON.stringify(data, null, 2);
      } catch (e) {
        out.textContent = 'Error: ' + e;
      }
    }
    function copyText(text, msg) {
      navigator.clipboard.writeText(text).then(() => showToast(msg)).catch(() => prompt('Copy:', text));
    }
    function showToast(msg) {
      const t = document.getElementById('toast');
      t.textContent = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 2500);
    }
  </script>
</body>
</html>''';
  }
}
