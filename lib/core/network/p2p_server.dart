import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart';
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
typedef DeleteMessageCallback = void Function(String messageId, [String? senderId]);
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

  // Real-time server diagnostics & performance metrics
  int _totalRequestsCount = 0;
  int _totalMessagesReceived = 0;
  int _totalBytesSent = 0;
  int _totalBytesReceived = 0;

  // Active WebSocket connections: peerId -> WebSocket
  final Map<String, WebSocket> _activeSockets = {};
  // All opened WebSockets (including pre-auth)
  final Set<WebSocket> _openWebSockets = {};

  // Active files available for download: transferId -> File
  final Map<String, File> _sharedFiles = {};

  // Web Messenger in-memory thread (for browser visitor chat)
  final List<Map<String, dynamic>> _webMessages = [];
  List<Map<String, dynamic>> get webMessages => List.unmodifiable(_webMessages);

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
  void Function(File file, String originalFileName)? onFileUploadedViaApi;

  void broadcastWebMessage({
    required String content,
    required String senderName,
    bool isMe = true,
  }) {
    final msg = {
      'id': 'web_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      'senderName': senderName,
      'content': content,
      'isMe': isMe,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _webMessages.add(msg);
    if (_webMessages.length > 100) {
      _webMessages.removeAt(0);
    }
    final payload = jsonEncode({
      'type': 'WEB_MSG',
      ...msg,
    });
    for (final ws in _openWebSockets) {
      if (ws.readyState == WebSocket.open) {
        try {
          ws.add(payload);
        } catch (_) {}
      }
    }
  }

  int get port => _actualPort;

  DateTime? get startedAt => _startedAt;

  Duration get uptime =>
      _startedAt != null ? DateTime.now().difference(_startedAt!) : Duration.zero;

  String get uptimeFormatted {
    final d = uptime;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  int get activeConnectionCount => _activeSockets.length;
  int get totalOpenSockets => _openWebSockets.length;
  int get sharedFilesCount => _sharedFiles.length;
  int get totalRequestsCount => _totalRequestsCount;
  int get totalMessagesReceived => _totalMessagesReceived;
  int get totalBytesSent => _totalBytesSent;
  int get totalBytesReceived => _totalBytesReceived;

  /// Returns the active open WebSocket for a peer if connected
  WebSocket? getActiveSocket(String peerId) {
    final socket = _activeSockets[peerId];
    if (socket != null && socket.readyState == WebSocket.open) {
      return socket;
    }
    if (socket != null) {
      _activeSockets.remove(peerId);
    }
    return null;
  }

  /// Checks whether an open active incoming connection exists for a peer
  bool hasActiveSocket(String peerId) => getActiveSocket(peerId) != null;

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

  /// Starts the embedded HTTP & WebSocket server with robust binding and fallback
  Future<int> start() async {
    await stop();

    HttpServer? boundServer;

    // 1. Attempt requested port with shared socket capability
    try {
      boundServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        requestedPort,
        shared: true,
      );
    } catch (_) {
      // 2. Sequential fallback attempts for predictable LAN clustering
      for (int offset = 1; offset <= 4; offset++) {
        try {
          boundServer = await HttpServer.bind(
            InternetAddress.anyIPv4,
            requestedPort + offset,
            shared: true,
          );
          break;
        } catch (_) {}
      }
    }

    // 3. Dynamic IPv4 fallback
    if (boundServer == null) {
      try {
        boundServer = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: true,
        );
      } catch (_) {
        // 4. Dual-stack / IPv6 fallback if IPv4 stack is restricted
        try {
          boundServer = await HttpServer.bind(
            InternetAddress.anyIPv6,
            requestedPort,
            shared: true,
          );
        } catch (_) {
          boundServer = await HttpServer.bind(
            InternetAddress.anyIPv6,
            0,
            shared: true,
          );
        }
      }
    }

    _server = boundServer;
    _actualPort = _server!.port;
    _startedAt = DateTime.now();
    _server!.listen(
      _handleHttpRequest,
      onError: (error, stackTrace) {
        if (kDebugMode) print('[P2pServer] Server socket error: $error');
      },
      cancelOnError: false,
    );

    return _actualPort;
  }

  void registerSharedFile(String transferId, File file) {
    _sharedFiles[transferId] = file;
  }

  void unregisterSharedFile(String transferId) {
    _sharedFiles.remove(transferId);
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    _totalRequestsCount++;

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

    // Favicon handler to avoid 404 logs in browsers
    if (path == '/favicon.ico') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    // Fast Ping / Latency Check API
    if (path == '/api/ping') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'pong': true,
        'app': 'OZO',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'port': _actualPort,
        'uptimeSeconds': uptime.inSeconds,
      }));
      await request.response.close();
      return;
    }

    // WebSocket upgrade for real-time E2EE communication
    if (path == '/ws') {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.pingInterval = const Duration(seconds: 15);
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
      final uptimeSec = uptime.inSeconds;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'OZO',
        'version': '1.1.0',
        'protocol': AppConstants.protocolVersion,
        'id': deviceId,
        'name': deviceName,
        'pubKey': cryptoService.publicKeyBase64,
        'safetyFingerprint': safetyFingerprint,
        'status': 'online',
        'port': _actualPort,
        'uptimeSeconds': uptimeSec,
        'uptime': uptimeFormatted,
        'activeConnections': _activeSockets.length,
        'sharedFilesCount': _sharedFiles.length,
        'activePeers': _activeSockets.keys.toList(),
        'platform': Platform.operatingSystem,
        'endpoints': {
          'web': '/',
          'ws': '/ws',
          'ping': '/api/ping',
          'info': '/api/info',
          'connect': '/api/connect',
          'health': '/api/health',
          'files': '/api/files',
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
            'pubKey': cryptoService.publicKeyBase64,
            'port': _actualPort,
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
      final uptimeSec = uptime.inSeconds;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'healthy',
        'app': 'OZO',
        'version': '1.1.0',
        'protocol': AppConstants.protocolVersion,
        'serverPort': _actualPort,
        'uptimeSeconds': uptimeSec,
        'uptime': uptimeFormatted,
        'activeConnections': _activeSockets.length,
        'totalOpenSockets': _openWebSockets.length,
        'sharedFilesCount': _sharedFiles.length,
        'totalRequests': _totalRequestsCount,
        'totalMessages': _totalMessagesReceived,
        'totalBytesSent': _totalBytesSent,
        'totalBytesReceived': _totalBytesReceived,
        'platform': Platform.operatingSystem,
      }));
      await request.response.close();
      return;
    }

    // List Available Shared Files API
    if (path == '/api/files') {
      final fileList = <Map<String, dynamic>>[];
      for (final entry in _sharedFiles.entries) {
        final transferId = entry.key;
        final file = entry.value;
        final exists = await file.exists();
        final length = exists ? await file.length() : 0;
        final fileName = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'file';
        fileList.add({
          'transferId': transferId,
          'fileName': fileName,
          'fileSize': length,
          'downloadUrl': '/api/file/download/$transferId',
        });
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'count': fileList.length,
        'files': fileList,
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

    // Web Messenger API: Send message
    if (path == '/api/message' && request.method == 'POST') {
      try {
        final body = await utf8.decodeStream(request);
        final json = jsonDecode(body) as Map<String, dynamic>;
        final text = (json['text'] as String?)?.trim() ?? '';
        final senderName = (json['senderName'] as String?)?.trim() ?? 'Web Visitor';
        if (text.isNotEmpty) {
          final msgId = 'web_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
          final webMsgMap = {
            'id': msgId,
            'senderName': senderName,
            'content': text,
            'isMe': false,
            'timestamp': DateTime.now().toIso8601String(),
          };
          _webMessages.add(webMsgMap);
          if (_webMessages.length > 100) {
            _webMessages.removeAt(0);
          }

          // Broadcast to any open web socket viewers
          final wsPayload = jsonEncode({
            'type': 'WEB_MSG',
            ...webMsgMap,
          });
          for (final ws in _openWebSockets) {
            if (ws.readyState == WebSocket.open) {
              try {
                ws.add(wsPayload);
              } catch (_) {}
            }
          }

          // Ingest into ChatProvider as incoming message from Web Visitor
          final chatMsg = ChatMessage(
            id: msgId,
            chatId: 'web_visitor',
            senderId: 'web_client',
            senderName: senderName,
            recipientId: deviceId,
            content: text,
            type: MessageType.text,
            timestamp: DateTime.now(),
            status: MessageStatus.delivered,
          );
          onMessageReceived?.call(chatMsg);

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'success': true, 'message': 'Delivered to OZO host'}));
          await request.response.close();
          return;
        }
      } catch (e) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': false, 'error': e.toString()}));
        await request.response.close();
        return;
      }
    }

    // Web Messenger API: Get recent messages
    if (path == '/api/messages') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'messages': _webMessages,
      }));
      await request.response.close();
      return;
    }

    // Web Drop File Upload endpoint
    if (path == '/api/upload' && request.method == 'POST') {
      await _handleFileUpload(request);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> _handleFileUpload(HttpRequest request) async {
    try {
      String fileName = request.headers.value('x-filename') ?? '';
      if (fileName.isNotEmpty) {
        fileName = Uri.decodeComponent(fileName);
      } else {
        final disposition = request.headers.value('content-disposition');
        if (disposition != null) {
          final match = RegExp(r'filename="?([^"]+)"?').firstMatch(disposition);
          if (match != null) {
            fileName = match.group(1) ?? '';
          }
        }
      }
      if (fileName.isEmpty) {
        fileName = 'web_upload_${DateTime.now().millisecondsSinceEpoch}.bin';
      }

      Directory uploadDir;
      try {
        final tempDir = await getTemporaryDirectory();
        uploadDir = Directory(p.join(tempDir.path, 'ozo_web_uploads'));
      } catch (_) {
        uploadDir = Directory(p.join(Directory.systemTemp.path, 'ozo_web_uploads'));
      }
      if (!await uploadDir.exists()) {
        await uploadDir.create(recursive: true);
      }

      final savedFile = File(p.join(uploadDir.path, fileName));
      final sink = savedFile.openWrite();
      await sink.addStream(request);
      await sink.close();

      final fileSize = await savedFile.length();

      // Register as a shared file as well so web users can download it
      final transferId = 'up_${DateTime.now().millisecondsSinceEpoch}';
      _sharedFiles[transferId] = savedFile;

      // Broadcast system web message announcing the file
      final fileNotice = {
        'id': 'web_${DateTime.now().millisecondsSinceEpoch}',
        'senderName': 'System',
        'content': '📁 Shared file: $fileName (${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB)',
        'isMe': false,
        'fileUrl': '/api/file/download/$transferId',
        'fileName': fileName,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _webMessages.add(fileNotice);
      for (final ws in _openWebSockets) {
        if (ws.readyState == WebSocket.open) {
          try {
            ws.add(jsonEncode({'type': 'WEB_MSG', ...fileNotice}));
          } catch (_) {}
        }
      }

      onFileUploadedViaApi?.call(savedFile, fileName);

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'fileName': fileName,
        'fileSize': fileSize,
        'downloadUrl': '/api/file/download/$transferId',
        'message': 'File uploaded and received by OZO successfully.',
      }));
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': false, 'error': e.toString()}));
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  ContentType _resolveContentType(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1) return ContentType.binary;
    final ext = path.substring(dotIndex + 1).toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'png':
        return ContentType('image', 'png');
      case 'gif':
        return ContentType('image', 'gif');
      case 'webp':
        return ContentType('image', 'webp');
      case 'svg':
        return ContentType('image', 'svg+xml');
      case 'mp4':
        return ContentType('video', 'mp4');
      case 'webm':
        return ContentType('video', 'webm');
      case 'mp3':
        return ContentType('audio', 'mpeg');
      case 'm4a':
      case 'aac':
        return ContentType('audio', 'aac');
      case 'wav':
        return ContentType('audio', 'wav');
      case 'ogg':
      case 'opus':
        return ContentType('audio', 'ogg');
      case 'pdf':
        return ContentType('application', 'pdf');
      case 'json':
        return ContentType.json;
      case 'txt':
        return ContentType.text;
      case 'zip':
        return ContentType('application', 'zip');
      default:
        return ContentType.binary;
    }
  }

  Future<void> _handleFileDownload(HttpRequest request, String transferId) async {
    final file = _sharedFiles[transferId];
    if (file == null || !await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('File not found or transfer expired');
      try {
        await request.response.close();
      } catch (_) {}
      return;
    }

    final fileSize = await file.length();
    final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file';
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
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $startByte-$endByte/$fileSize');
    } else {
      request.response.statusCode = HttpStatus.ok;
    }

    final contentLength = endByte - startByte + 1;
    request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());
    request.response.headers.contentType = _resolveContentType(file.path);
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final sanitizedFileName = fileName.replaceAll('"', '');
    request.response.headers.set('Content-Disposition', 'inline; filename="$sanitizedFileName"');

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
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
        _totalBytesSent += chunk.length;
      }
    } catch (e) {
      if (kDebugMode) print('[P2pServer] File stream interrupted: $e');
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  void _handleWebSocket(WebSocket socket, String remoteIp) {
    _openWebSockets.add(socket);
    String? peerId;

    socket.listen(
      (data) async {
        try {
          // Payload protection: guard against excessive frame size (16MB limit)
          if (data is String && data.length > 16 * 1024 * 1024) {
            if (kDebugMode) print('[P2pServer] WS dropped frame: oversized text payload');
            return;
          } else if (data is List<int> && data.length > 16 * 1024 * 1024) {
            if (kDebugMode) print('[P2pServer] WS dropped frame: oversized binary payload');
            return;
          }

          final text = data is String ? data : utf8.decode(data as List<int>);
          _totalBytesReceived += text.length;
          _totalMessagesReceived++;

          final msg = jsonDecode(text) as Map<String, dynamic>;

          final type = msg['type'] as String?;
          final senderId = msg['senderId'] as String?;

          if (senderId != null) {
            peerId = senderId;
            _activeSockets[senderId] = socket;
          }

          switch (type) {
            case 'PING':
              if (socket.readyState == WebSocket.open) {
                socket.add(jsonEncode({
                  'type': 'PONG',
                  'ts': DateTime.now().millisecondsSinceEpoch,
                  'echo': msg['ts'],
                }));
              }
              break;
            case 'PONG':
              // Keepalive acknowledged
              break;
            case 'HANDSHAKE':
              if (socket.readyState == WebSocket.open) {
                socket.add(jsonEncode({
                  'type': 'HANDSHAKE_ACK',
                  'senderId': deviceId,
                  'senderName': deviceName,
                  'senderPubKey': cryptoService.publicKeyBase64,
                  'ts': DateTime.now().millisecondsSinceEpoch,
                }));
              }
              break;
            case 'HANDSHAKE_ACK':
              break;
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
              final reqSenderId = msg['senderId'] as String? ?? peerId;
              onMessageDeleted?.call(messageId, reqSenderId);
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
            case 'WEB_MSG':
              final content = (msg['content'] as String?)?.trim() ?? '';
              final sender = (msg['senderName'] as String?)?.trim() ?? 'Web Visitor';
              if (content.isNotEmpty) {
                final msgId = msg['id'] as String? ?? 'web_${DateTime.now().millisecondsSinceEpoch}';
                final item = {
                  'id': msgId,
                  'senderName': sender,
                  'content': content,
                  'isMe': false,
                  'timestamp': DateTime.now().toIso8601String(),
                };
                _webMessages.add(item);
                if (_webMessages.length > 100) _webMessages.removeAt(0);

                // Broadcast to other open web sockets
                for (final ws in _openWebSockets) {
                  if (ws != socket && ws.readyState == WebSocket.open) {
                    try {
                      ws.add(jsonEncode({'type': 'WEB_MSG', ...item}));
                    } catch (_) {}
                  }
                }

                final chatMsg = ChatMessage(
                  id: msgId,
                  chatId: 'web_visitor',
                  senderId: 'web_client',
                  senderName: sender,
                  recipientId: deviceId,
                  content: content,
                  type: MessageType.text,
                  timestamp: DateTime.now(),
                  status: MessageStatus.delivered,
                );
                onMessageReceived?.call(chatMsg);
              }
              break;
          }
        } catch (e) {
          if (kDebugMode) print('WS parse error: $e');
        }
      },
      onDone: () {
        _openWebSockets.remove(socket);
        if (peerId != null) {
          _activeSockets.remove(peerId);
        } else {
          _activeSockets.removeWhere((k, v) => identical(v, socket));
        }
      },
      onError: (err) {
        _openWebSockets.remove(socket);
        if (peerId != null) {
          _activeSockets.remove(peerId);
        } else {
          _activeSockets.removeWhere((k, v) => identical(v, socket));
        }
      },
      cancelOnError: true,
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
      if (kDebugMode) print('E2EE Decryption failed from $senderId: $e');
      return; // Reject and drop unauthenticated/tampered message
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
    final ephemeralSec = msg['ephemeralSeconds'] as int?;
    final expAt = ephemeralSec != null ? DateTime.now().add(Duration(seconds: ephemeralSec)) : null;

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
      ephemeralDurationSeconds: ephemeralSec,
      expiresAt: expAt,
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
      final ephemeralSec = msg['ephemeralSeconds'] as int?;
      final expAt = ephemeralSec != null ? DateTime.now().add(Duration(seconds: ephemeralSec)) : null;

      final msgTypeStr = msg['msgType'] as String?;
      var msgType = MessageType.values.firstWhere(
        (e) => e.name == msgTypeStr,
        orElse: () => MessageType.text,
      );
      if (msgType == MessageType.text &&
          (content.startsWith('{"latitude"') || content.startsWith('{"latitude":')) &&
          LocationData.tryParse(content) != null) {
        msgType = MessageType.location;
      }

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
        chatId: groupId,
        senderId: senderId,
        senderName: senderName,
        recipientId: groupId,
        content: content,
        type: msgType,
        timestamp: timestamp,
        status: MessageStatus.delivered,
        isGroup: true,
        groupId: groupId,
        voiceDurationSeconds: voiceDuration,
        waveformAmplitudes: amplitudes,
        fileMetadata: fileMeta,
        replyToId: replyToId,
        replyToText: replyToText,
        replyToSenderName: replyToSenderName,
        ephemeralDurationSeconds: ephemeralSec,
        expiresAt: expAt,
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
    for (final socket in _openWebSockets.toList()) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _openWebSockets.clear();
    _activeSockets.clear();
    _sharedFiles.clear();

    await _server?.close(force: true);
    _server = null;
    _actualPort = 0;
  }

  String _generateQrSvg(String data) {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);
      final count = qrImage.moduleCount;
      final buf = StringBuffer();
      buf.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $count $count" width="180" height="180" shape-rendering="crispEdges">');
      buf.write('<rect width="100%" height="100%" fill="#ffffff" rx="14"/>');
      for (var r = 0; r < count; r++) {
        for (var c = 0; c < count; c++) {
          if (qrImage.isDark(r, c)) {
            buf.write('<rect x="$c" y="$r" width="1" height="1" fill="#000000"/>');
          }
        }
      }
      buf.write('</svg>');
      return buf.toString();
    } catch (_) {
      return '<div style="padding:20px;color:#888;font-size:12px;">QR Code generated for OZO link</div>';
    }
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
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>OZO P2P • Connect to $safeName</title>
  <style>
    :root {
      --bg: #0b0e14;
      --card-bg: rgba(22, 27, 34, 0.75);
      --card-border: rgba(255, 255, 255, 0.08);
      --card-border-active: rgba(88, 166, 255, 0.4);
      --text-main: #f0f6fc;
      --text-muted: #8b949e;
      --accent: #2f81f7;
      --accent-gradient: linear-gradient(135deg, #2f81f7 0%, #388bfd 100%);
      --accent-hover: #1f6feb;
      --green: #3fb950;
      --green-bg: rgba(63, 185, 80, 0.15);
      --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Segoe UI", Roboto, sans-serif;
      --radius: 20px;
      --shadow: 0 16px 36px rgba(0, 0, 0, 0.45);
    }
    @media (prefers-color-scheme: light) {
      :root {
        --bg: #f4f6f8;
        --card-bg: rgba(255, 255, 255, 0.85);
        --card-border: rgba(0, 0, 0, 0.08);
        --card-border-active: rgba(9, 105, 218, 0.35);
        --text-main: #1f2328;
        --text-muted: #656d76;
        --accent: #0969da;
        --accent-gradient: linear-gradient(135deg, #0969da 0%, #218bff 100%);
        --accent-hover: #0860ca;
        --green: #1a7f37;
        --green-bg: rgba(31, 136, 61, 0.12);
        --shadow: 0 12px 32px rgba(0, 0, 0, 0.08);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 32px 16px 48px;
      font-family: var(--font);
      background-color: var(--bg);
      color: var(--text-main);
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      -webkit-font-smoothing: antialiased;
    }
    .container {
      width: 100%;
      max-width: 480px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .glass-card {
      background: var(--card-bg);
      backdrop-filter: blur(24px);
      -webkit-backdrop-filter: blur(24px);
      border: 1px solid var(--card-border);
      border-radius: var(--radius);
      padding: 24px;
      box-shadow: var(--shadow);
      transition: border-color 0.2s;
    }
    .header {
      text-align: center;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 6px;
    }
    .app-icon {
      width: 58px;
      height: 58px;
      border-radius: 16px;
      background: var(--accent-gradient);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 8px 20px rgba(47, 129, 247, 0.35);
      margin-bottom: 4px;
    }
    .app-icon svg { width: 32px; height: 32px; fill: #ffffff; }
    h1 {
      margin: 4px 0 0;
      font-size: 24px;
      font-weight: 700;
      letter-spacing: -0.5px;
    }
    .sub {
      color: var(--text-muted);
      font-size: 13px;
      margin: 0;
    }
    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 5px 12px;
      border-radius: 20px;
      background: var(--green-bg);
      color: var(--green);
      font-size: 12px;
      font-weight: 600;
      margin-top: 6px;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--green);
      box-shadow: 0 0 10px var(--green);
      animation: pulse 2s infinite ease-in-out;
    }
    @keyframes pulse {
      0%, 100% { transform: scale(1); opacity: 1; }
      50% { transform: scale(1.2); opacity: 0.7; }
    }
    .segmented-control {
      display: flex;
      background: rgba(120, 120, 128, 0.16);
      padding: 4px;
      border-radius: 12px;
      gap: 4px;
      margin-bottom: 12px;
    }
    .segment-btn {
      flex: 1;
      border: none;
      background: transparent;
      padding: 8px 12px;
      font-size: 13px;
      font-weight: 600;
      color: var(--text-muted);
      border-radius: 9px;
      cursor: pointer;
      transition: all 0.2s;
    }
    .segment-btn.active {
      background: var(--card-bg);
      color: var(--text-main);
      box-shadow: 0 3px 8px rgba(0,0,0,0.12);
    }
    .tab-content { display: none; }
    .tab-content.active { display: block; }
    .info-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 10px 0;
      border-bottom: 1px solid var(--card-border);
      font-size: 13px;
    }
    .info-row:last-child { border-bottom: none; }
    .info-label { color: var(--text-muted); }
    .info-val { font-weight: 600; font-family: ui-monospace, monospace; }
    .fingerprint {
      color: var(--accent);
      font-weight: 700;
      letter-spacing: 0.5px;
    }
    .qr-wrap {
      display: flex;
      justify-content: center;
      margin: 16px 0;
    }
    .qr-card {
      background: #ffffff;
      padding: 14px;
      border-radius: 18px;
      box-shadow: 0 6px 20px rgba(0,0,0,0.15);
    }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      padding: 13px;
      border-radius: 12px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      border: none;
      transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
    }
    .btn:active { transform: scale(0.98); }
    .btn-primary {
      background: var(--accent-gradient);
      color: #ffffff;
      box-shadow: 0 4px 14px rgba(47, 129, 247, 0.28);
    }
    .btn-primary:hover {
      background: var(--accent-hover);
    }
    .btn-secondary {
      background: rgba(120, 120, 128, 0.12);
      color: var(--text-main);
      margin-top: 8px;
    }
    .btn-secondary:hover {
      background: rgba(120, 120, 128, 0.2);
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 10px;
      margin-bottom: 16px;
    }
    .stat-card {
      background: rgba(120, 120, 128, 0.08);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 12px;
    }
    .stat-num {
      font-size: 18px;
      font-weight: 700;
      color: var(--text-main);
      font-family: ui-monospace, monospace;
      margin-top: 4px;
    }
    .stat-title {
      font-size: 11px;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .probe-box {
      background: rgba(120, 120, 128, 0.08);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 14px;
      margin-bottom: 10px;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .probe-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .probe-badge {
      font-size: 12px;
      font-weight: 600;
      font-family: ui-monospace, monospace;
    }
    .endpoint-item {
      background: rgba(120, 120, 128, 0.08);
      border: 1px solid var(--card-border);
      border-radius: 10px;
      padding: 10px 12px;
      margin-bottom: 8px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-family: ui-monospace, monospace;
      font-size: 12px;
    }
    .method-tag {
      font-weight: 700;
      color: var(--accent);
      margin-right: 6px;
    }
    .action-pill {
      background: rgba(47, 129, 247, 0.15);
      color: var(--accent);
      border: 1px solid rgba(47, 129, 247, 0.3);
      border-radius: 8px;
      padding: 4px 10px;
      font-size: 11px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    }
    .action-pill:hover {
      background: rgba(47, 129, 247, 0.3);
    }
    pre.code-out {
      background: #0d1117;
      border: 1px solid var(--card-border);
      border-radius: 10px;
      padding: 12px;
      font-size: 11px;
      line-height: 1.45;
      color: #7ee787;
      overflow-x: auto;
      max-height: 220px;
      margin-top: 10px;
    }
    .toast {
      position: fixed;
      bottom: 24px;
      background: rgba(30, 36, 46, 0.95);
      color: #ffffff;
      padding: 10px 20px;
      border-radius: 30px;
      font-size: 13px;
      font-weight: 500;
      box-shadow: 0 8px 24px rgba(0,0,0,0.3);
      display: none;
      z-index: 1000;
      border: 1px solid rgba(255,255,255,0.1);
      animation: fadeIn 0.2s ease-out;
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }
    /* Web Messenger & Dropzone Styles */
    .dropzone {
      border: 2px dashed rgba(120, 120, 128, 0.35);
      border-radius: 14px;
      padding: 16px 12px;
      text-align: center;
      cursor: pointer;
      background: rgba(120, 120, 128, 0.05);
      transition: all 0.2s ease;
      margin-bottom: 12px;
    }
    .dropzone.dragover {
      border-color: var(--accent);
      background: rgba(47, 129, 247, 0.12);
      transform: scale(1.01);
    }
    .chat-thread {
      height: 250px;
      overflow-y: auto;
      display: flex;
      flex-direction: column;
      gap: 10px;
      padding: 10px;
      background: rgba(0, 0, 0, 0.15);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      margin-bottom: 12px;
      scroll-behavior: smooth;
    }
    .chat-msg {
      max-width: 82%;
      display: flex;
      flex-direction: column;
    }
    .chat-msg.in {
      align-self: flex-start;
    }
    .chat-msg.out {
      align-self: flex-end;
    }
    .msg-author {
      font-size: 10px;
      font-weight: 600;
      color: var(--text-muted);
      margin-bottom: 2px;
      padding-left: 4px;
    }
    .chat-msg.out .msg-author {
      text-align: right;
      padding-right: 4px;
    }
    .msg-bubble {
      padding: 9px 13px;
      border-radius: 16px;
      font-size: 13px;
      line-height: 1.4;
      word-break: break-word;
    }
    .chat-msg.in .msg-bubble {
      background: rgba(120, 120, 128, 0.18);
      color: var(--text-main);
      border-bottom-left-radius: 4px;
    }
    .chat-msg.out .msg-bubble {
      background: var(--accent-gradient);
      color: #ffffff;
      border-bottom-right-radius: 4px;
      box-shadow: 0 2px 8px rgba(47, 129, 247, 0.25);
    }
    .msg-file-card {
      display: flex;
      align-items: center;
      gap: 8px;
      background: rgba(0, 0, 0, 0.2);
      padding: 8px 10px;
      border-radius: 10px;
      margin-top: 4px;
      font-size: 12px;
    }
    .msg-time {
      font-size: 9px;
      color: var(--text-muted);
      margin-top: 2px;
      padding: 0 4px;
    }
    .chat-msg.out .msg-time {
      text-align: right;
    }
    .chat-input-bar {
      display: flex;
      gap: 8px;
      align-items: center;
    }
    .chat-input {
      flex: 1;
      background: rgba(120, 120, 128, 0.12);
      border: 1px solid var(--card-border);
      color: var(--text-main);
      padding: 10px 14px;
      border-radius: 20px;
      font-size: 13px;
      outline: none;
      transition: border-color 0.2s;
    }
    .chat-input:focus {
      border-color: var(--accent);
    }
    .chat-send-btn {
      width: 38px;
      height: 38px;
      border-radius: 50%;
      background: var(--accent-gradient);
      border: none;
      color: #ffffff;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      box-shadow: 0 3px 10px rgba(47, 129, 247, 0.3);
      transition: transform 0.15s;
    }
    .chat-send-btn:active {
      transform: scale(0.92);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="glass-card header">
      <div class="app-icon">
        <svg viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14.5v-9l6 4.5-6 4.5z"/>
        </svg>
      </div>
      <h1>$safeName</h1>
      <p class="sub">OZO P2P • End-to-End Encrypted Node</p>
      <div class="badge-status">
        <span class="dot"></span> Online &amp; Listening
      </div>
    </div>

    <div class="segmented-control">
      <button class="segment-btn active" onclick="switchTab('chat')">💬 Web Chat &amp; Drop</button>
      <button class="segment-btn" onclick="switchTab('connect')">📱 App Link</button>
      <button class="segment-btn" onclick="switchTab('diagnostics')">Diagnostics</button>
      <button class="segment-btn" onclick="switchTab('api')">API</button>
    </div>

    <!-- TAB 1: WEB CHAT & DROP -->
    <div id="tab-chat" class="tab-content active glass-card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
        <div>
          <div style="font-weight:700; font-size:15px;">Live LAN Messenger</div>
          <div style="font-size:11px; color:var(--text-muted);">Direct P2P link with $safeName</div>
        </div>
        <div id="ws-indicator" style="font-size:11px; font-weight:600; color:var(--green); display:flex; align-items:center; gap:5px;">
          <span style="width:6px; height:6px; border-radius:50%; background:var(--green); display:inline-block;"></span> Live
        </div>
      </div>

      <!-- Drag and Drop Dropzone -->
      <div id="drop-zone" class="dropzone" onclick="document.getElementById('file-input').click()">
        <input type="file" id="file-input" style="display:none" multiple onchange="handleFileSelect(this.files)">
        <div style="font-size:24px; margin-bottom:4px;">📥</div>
        <div style="font-size:13px; font-weight:600; color:var(--text-main);">Drop files here or click to send</div>
        <div style="font-size:11px; color:var(--text-muted); margin-top:2px;">Instant zero-size-limit LAN transfer</div>
      </div>
      <div id="upload-progress-container" style="display:none; margin-bottom:12px;">
        <div style="display:flex; justify-content:space-between; font-size:11px; margin-bottom:4px;">
          <span id="upload-filename" style="color:var(--text-main); font-weight:600;">Uploading...</span>
          <span id="upload-percent" style="color:var(--accent); font-weight:700;">0%</span>
        </div>
        <div style="background:rgba(120,120,128,0.2); border-radius:8px; height:6px; overflow:hidden;">
          <div id="upload-progress-bar" style="background:var(--accent); width:0%; height:100%; transition:width 0.15s ease;"></div>
        </div>
      </div>

      <!-- Chat Bubble Thread -->
      <div id="chat-thread" class="chat-thread">
        <div class="chat-msg in">
          <div class="msg-author">$safeName</div>
          <div class="msg-bubble">👋 Hello! You can chat and send files directly to my device over Wi-Fi without installing the app.</div>
          <div class="msg-time">Just now</div>
        </div>
      </div>

      <!-- Composer Input -->
      <div class="chat-input-bar">
        <input type="text" id="chat-input" class="chat-input" placeholder="Type a message to $safeName..." onkeydown="if(event.key==='Enter') sendWebMessage()">
        <button class="chat-send-btn" onclick="sendWebMessage()" title="Send">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"></line>
            <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
          </svg>
        </button>
      </div>
    </div>

    <!-- TAB 2: CONNECT -->
    <div id="tab-connect" class="tab-content glass-card">
      <div class="info-row">
        <span class="info-label">Peer Name</span>
        <span class="info-val">$safeName</span>
      </div>
      <div class="info-row">
        <span class="info-label">Device ID</span>
        <span class="info-val">${safeId.length > 14 ? '${safeId.substring(0, 14)}...' : safeId}</span>
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
        <div class="qr-card">${_generateQrSvg(deepLink)}</div>
      </div>

      <a href="$deepLink" class="btn btn-primary">📱 Open in OZO App</a>
      <button onclick="copyText('$deepLink', 'OZO connection link copied to clipboard!')" class="btn btn-secondary">📋 Copy Deep Link</button>
      <button onclick="copyText('$webUrl', 'Web URL copied to clipboard!')" class="btn btn-secondary">🌐 Copy Web Link</button>
    </div>

    <!-- TAB 3: DIAGNOSTICS & PROBES -->
    <div id="tab-diagnostics" class="tab-content glass-card">
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-title">Port</div>
          <div class="stat-num">$_actualPort</div>
        </div>
        <div class="stat-card">
          <div class="stat-title">Active Sockets</div>
          <div class="stat-num">${_activeSockets.length}</div>
        </div>
        <div class="stat-card">
          <div class="stat-title">Shared Files</div>
          <div class="stat-num">${_sharedFiles.length}</div>
        </div>
        <div class="stat-card">
          <div class="stat-title">Uptime</div>
          <div class="stat-num" id="uptime-val">$uptimeFormatted</div>
        </div>
      </div>

      <div class="probe-box">
        <div class="probe-row">
          <div>
            <div style="font-weight: 600; font-size: 13px;">WebSocket Probe</div>
            <div style="font-size: 11px; color: var(--text-muted);">Real-time E2EE socket ping</div>
          </div>
          <button id="ws-probe-btn" class="action-pill" onclick="testWsProbe('$wsUrl')">Ping WS</button>
        </div>
        <div id="ws-probe-result" class="probe-badge" style="color: var(--text-muted); font-size: 11px;">Ready to test</div>
      </div>

      <div class="probe-box">
        <div class="probe-row">
          <div>
            <div style="font-weight: 600; font-size: 13px;">HTTP Health Check</div>
            <div style="font-size: 11px; color: var(--text-muted);">REST server latency test</div>
          </div>
          <button id="http-probe-btn" class="action-pill" onclick="testHttpProbe()">Ping HTTP</button>
        </div>
        <div id="http-probe-result" class="probe-badge" style="color: var(--text-muted); font-size: 11px;">Ready to test</div>
      </div>
    </div>

    <!-- TAB 4: REST & WS API -->
    <div id="tab-api" class="tab-content glass-card">
      <div style="font-size: 13px; font-weight: 700; margin-bottom: 12px;">Node REST Endpoints</div>

      <div class="endpoint-item">
        <span><span class="method-tag">GET</span> /api/ping</span>
        <button class="action-pill" onclick="callApi('/api/ping')">Execute</button>
      </div>

      <div class="endpoint-item">
        <span><span class="method-tag">GET</span> /api/info</span>
        <button class="action-pill" onclick="callApi('/api/info')">Execute</button>
      </div>

      <div class="endpoint-item">
        <span><span class="method-tag">GET</span> /api/health</span>
        <button class="action-pill" onclick="callApi('/api/health')">Execute</button>
      </div>

      <div class="endpoint-item">
        <span><span class="method-tag">GET</span> /api/files</span>
        <button class="action-pill" onclick="callApi('/api/files')">Execute</button>
      </div>

      <div class="endpoint-item">
        <span><span class="method-tag">GET</span> /api/messages</span>
        <button class="action-pill" onclick="callApi('/api/messages')">Execute</button>
      </div>

      <div class="endpoint-item">
        <span><span class="method-tag">POST</span> /api/upload</span>
        <span style="font-size: 11px; color: var(--text-muted);">Drop files</span>
      </div>

      <div class="endpoint-item">
        <span><span class="method-tag">WS</span> /ws</span>
        <span style="font-size: 11px; color: var(--text-muted);">Full-Duplex</span>
      </div>

      <pre id="api-output" class="code-out" style="display:none;"></pre>
    </div>
  </div>

  <div id="toast" class="toast"></div>

  <script>
    let chatWs;
    const wsUrl = '$wsUrl';
    const seenMsgIds = new Set();

    function switchTab(tabId) {
      document.querySelectorAll('.segment-btn').forEach(btn => btn.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
      event.target.classList.add('active');
      document.getElementById('tab-' + tabId).classList.add('active');
    }

    function initChat() {
      setupDropzone();
      connectChatWs();
      loadInitialMessages();
      setInterval(pollMessages, 3000);
    }

    function connectChatWs() {
      try {
        chatWs = new WebSocket(wsUrl);
        chatWs.onopen = function() {
          const ind = document.getElementById('ws-indicator');
          if (ind) ind.innerHTML = '<span style="width:6px; height:6px; border-radius:50%; background:var(--green); display:inline-block;"></span> Live';
          chatWs.send(JSON.stringify({ type: 'HANDSHAKE' }));
        };
        chatWs.onmessage = function(event) {
          try {
            const data = JSON.parse(event.data);
            if (data.type === 'WEB_MSG') {
              appendChatMessage(data);
            }
          } catch(e) {}
        };
        chatWs.onclose = function() {
          const ind = document.getElementById('ws-indicator');
          if (ind) ind.innerHTML = '<span style="width:6px; height:6px; border-radius:50%; background:#ff7b72; display:inline-block;"></span> Reconnecting';
          setTimeout(connectChatWs, 3000);
        };
      } catch(e) {}
    }

    async function loadInitialMessages() {
      try {
        const res = await fetch('/api/messages');
        if (res.ok) {
          const data = await res.json();
          if (data.messages && Array.isArray(data.messages)) {
            data.messages.forEach(msg => appendChatMessage(msg));
          }
        }
      } catch(e) {}
    }

    async function pollMessages() {
      if (chatWs && chatWs.readyState === WebSocket.OPEN) return;
      try {
        const res = await fetch('/api/messages');
        if (res.ok) {
          const data = await res.json();
          if (data.messages && Array.isArray(data.messages)) {
            data.messages.forEach(msg => appendChatMessage(msg));
          }
        }
      } catch(e) {}
    }

    function appendChatMessage(msg) {
      if (msg.id && seenMsgIds.has(msg.id)) return;
      if (msg.id) seenMsgIds.add(msg.id);

      const thread = document.getElementById('chat-thread');
      if (!thread) return;

      const isOut = msg.isMe === true || msg.senderName === 'Web Visitor';
      const msgDiv = document.createElement('div');
      msgDiv.className = 'chat-msg ' + (isOut ? 'out' : 'in');

      let fileHtml = '';
      if (msg.fileUrl) {
        fileHtml = '<div class="msg-file-card"><span>📎</span><span style="flex:1; overflow:hidden; text-overflow:ellipsis;">' + (msg.fileName || 'File') + '</span><a href="' + msg.fileUrl + '" download style="color:var(--accent); text-decoration:none; font-weight:700;">⬇️ Download</a></div>';
      }

      const timeStr = msg.timestamp ? new Date(msg.timestamp).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}) : 'Now';

      msgDiv.innerHTML =
        '<div class="msg-author">' + (msg.senderName || 'Anonymous') + '</div>' +
        '<div class="msg-bubble">' + escapeHtml(msg.content) + fileHtml + '</div>' +
        '<div class="msg-time">' + timeStr + '</div>';

      thread.appendChild(msgDiv);
      thread.scrollTop = thread.scrollHeight;
    }

    function escapeHtml(text) {
      if (!text) return '';
      const div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }

    async function sendWebMessage() {
      const input = document.getElementById('chat-input');
      const text = input.value.trim();
      if (!text) return;

      input.value = '';
      const tempId = 'web_' + Date.now();
      const localMsg = {
        id: tempId,
        senderName: 'You (Web)',
        content: text,
        isMe: true,
        timestamp: new Date().toISOString()
      };
      appendChatMessage(localMsg);

      if (chatWs && chatWs.readyState === WebSocket.OPEN) {
        chatWs.send(JSON.stringify({
          type: 'WEB_MSG',
          id: tempId,
          content: text,
          senderName: 'Web Visitor'
        }));
      } else {
        try {
          await fetch('/api/message', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({text: text, senderName: 'Web Visitor'})
          });
        } catch(e) {
          showToast('Failed to send message: ' + e);
        }
      }
    }

    function setupDropzone() {
      const dropZone = document.getElementById('drop-zone');
      if (!dropZone) return;

      ['dragenter', 'dragover'].forEach(name => {
        dropZone.addEventListener(name, (e) => {
          e.preventDefault();
          e.stopPropagation();
          dropZone.classList.add('dragover');
        });
      });

      ['dragleave', 'drop'].forEach(name => {
        dropZone.addEventListener(name, (e) => {
          e.preventDefault();
          e.stopPropagation();
          dropZone.classList.remove('dragover');
        });
      });

      dropZone.addEventListener('drop', (e) => {
        const files = e.dataTransfer.files;
        handleFileSelect(files);
      });
    }

    function handleFileSelect(files) {
      if (!files || files.length === 0) return;
      for (let i = 0; i < files.length; i++) {
        uploadFile(files[i]);
      }
    }

    function uploadFile(file) {
      const progressContainer = document.getElementById('upload-progress-container');
      const progressBar = document.getElementById('upload-progress-bar');
      const progressPercent = document.getElementById('upload-percent');
      const progressName = document.getElementById('upload-filename');

      progressContainer.style.display = 'block';
      progressName.textContent = file.name;
      progressBar.style.width = '0%';
      progressPercent.textContent = '0%';

      const xhr = new XMLHttpRequest();
      xhr.open('POST', '/api/upload', true);
      xhr.setRequestHeader('x-filename', encodeURIComponent(file.name));

      xhr.upload.onprogress = function(e) {
        if (e.lengthComputable) {
          const percent = Math.round((e.loaded / e.total) * 100);
          progressBar.style.width = percent + '%';
          progressPercent.textContent = percent + '%';
        }
      };

      xhr.onload = function() {
        progressContainer.style.display = 'none';
        if (xhr.status === 200) {
          showToast('File "' + file.name + '" uploaded successfully!');
          appendChatMessage({
            id: 'up_' + Date.now(),
            senderName: 'You (Web)',
            content: '📤 Uploaded file: ' + file.name,
            isMe: true,
            timestamp: new Date().toISOString()
          });
        } else {
          showToast('Upload failed with status ' + xhr.status);
        }
      };

      xhr.onerror = function() {
        progressContainer.style.display = 'none';
        showToast('Network error during file upload');
      };

      xhr.send(file);
    }

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

    async function testHttpProbe() {
      const btn = document.getElementById('http-probe-btn');
      const resEl = document.getElementById('http-probe-result');
      btn.disabled = true;
      resEl.textContent = 'Testing...';
      const start = performance.now();
      try {
        const res = await fetch('/api/ping');
        const elapsed = (performance.now() - start).toFixed(1);
        if (res.ok) {
          resEl.innerHTML = '<span style="color:var(--green)">● HTTP 200 OK</span> (' + elapsed + ' ms)';
        } else {
          resEl.innerHTML = '<span style="color:#ff7b72">HTTP ' + res.status + '</span> (' + elapsed + ' ms)';
        }
      } catch (e) {
        resEl.innerHTML = '<span style="color:#ff7b72">Failed: ' + e + '</span>';
      } finally {
        btn.disabled = false;
      }
    }

    function testWsProbe(probeWsUrl) {
      const btn = document.getElementById('ws-probe-btn');
      const resEl = document.getElementById('ws-probe-result');
      btn.disabled = true;
      resEl.textContent = 'Connecting WebSocket...';
      const start = performance.now();
      let socket;
      try {
        socket = new WebSocket(probeWsUrl);
        socket.onopen = function() {
          socket.send(JSON.stringify({ type: 'PING', ts: Date.now() }));
        };
        socket.onmessage = function(event) {
          const elapsed = (performance.now() - start).toFixed(1);
          resEl.innerHTML = '<span style="color:var(--green)">● WebSocket Connected</span> (' + elapsed + ' ms RTT)';
          socket.close();
          btn.disabled = false;
        };
        socket.onerror = function(err) {
          resEl.innerHTML = '<span style="color:#ff7b72">Connection error</span>';
          btn.disabled = false;
        };
      } catch (e) {
        resEl.innerHTML = '<span style="color:#ff7b72">Exception: ' + e + '</span>';
        btn.disabled = false;
      }
    }

    function copyText(text, msg) {
      navigator.clipboard.writeText(text).then(() => showToast(msg)).catch(() => prompt('Copy:', text));
    }

    function showToast(msg) {
      const t = document.getElementById('toast');
      t.textContent = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 2400);
    }

    window.addEventListener('DOMContentLoaded', initChat);
  </script>
</body>
</html>''';
  }

  String _escapeHtml(String text) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(text);
  }
}
