import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';
import '../database/models.dart';
import '../network/p2p_client.dart';
import '../network/p2p_server.dart';

typedef TransferUpdateCallback = void Function(FileTransferInfo info);

/// Manages chunked, resumable file transfers over LAN
class FileTransferManager extends ChangeNotifier {
  final P2pServer server;
  final P2pClient client;
  final AppDatabase database;
  final Directory? customDownloadDirectory;

  // Active transfers: transferId -> FileTransferInfo
  final Map<String, FileTransferInfo> _transfers = {};
  // Active HTTP client requests to allow cancellation/pausing: transferId -> HttpClient
  final Map<String, HttpClient> _activeClients = {};

  List<FileTransferInfo> get activeTransfers => _transfers.values.toList();

  FileTransferManager({
    required this.server,
    required this.client,
    required this.database,
    this.customDownloadDirectory,
  });

  FileTransferInfo? getTransfer(String transferId) => _transfers[transferId];

  /// Initiates an outgoing file offer to a peer
  Future<String?> offerFile({
    required Peer peer,
    required File file,
    required String messageId,
    required String myPlatform,
  }) async {
    if (!await file.exists()) return null;

    final fileName = p.basename(file.path);
    final fileSize = await file.length();

    // Calculate SHA-256 checksum
    final sha256Hash = await _calculateFileSha256(file);
    final transferId = '${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}';

    // Register file on local HTTP server for download
    server.registerSharedFile(transferId, file);

    final transferInfo = FileTransferInfo(
      transferId: transferId,
      messageId: messageId,
      fileName: fileName,
      fileSize: fileSize,
      bytesTransferred: 0,
      localPath: file.path,
      remoteIp: peer.ip,
      remotePort: peer.port,
      remotePublicKey: peer.publicKey,
      direction: TransferDirection.upload,
      status: TransferStatus.transferring,
      sha256: sha256Hash,
    );

    _transfers[transferId] = transferInfo;
    notifyListeners();

    // Send file offer to peer via WebSocket
    final ok = await client.sendFileOffer(
      peer: peer,
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256Hash,
      myPort: server.port,
      myPlatform: myPlatform,
    );

    if (!ok) {
      transferInfo.status = TransferStatus.failed;
      notifyListeners();
      return null;
    }

    return transferId;
  }

  /// Accepts an incoming file offer and begins chunked HTTP range download
  Future<void> acceptAndDownload({
    required FileMetadata metadata,
    required Peer sender,
    required String messageId,
  }) async {
    final transferId = metadata.transferId;

    // Resolve download destination directory & sanitize fileName to prevent path traversal
    final Directory downloadDir = await _getDownloadDirectory();
    var safeFileName = p.basename(metadata.fileName).replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (safeFileName.trim().isEmpty) {
      safeFileName = 'download_${metadata.transferId.substring(0, 8)}';
    }

    var destinationPath = p.join(downloadDir.path, safeFileName);
    var destFile = File(destinationPath);

    int existingBytes = 0;
    if (await destFile.exists()) {
      // Check if existing file is already the exact target file via SHA-256
      try {
        final existingHash = await _calculateFileSha256(destFile);
        if (metadata.sha256.isNotEmpty && existingHash == metadata.sha256) {
          metadata.localPath = destinationPath;
          metadata.isCompleted = true;
          await database.markFileCompleted(transferId, destinationPath);
          _transfers[transferId] = FileTransferInfo(
            transferId: transferId,
            messageId: messageId,
            fileName: safeFileName,
            fileSize: metadata.fileSize,
            bytesTransferred: metadata.fileSize,
            localPath: destinationPath,
            remoteIp: sender.ip,
            remotePort: sender.port,
            remotePublicKey: sender.publicKey,
            direction: TransferDirection.download,
            status: TransferStatus.completed,
            sha256: metadata.sha256,
          );
          notifyListeners();
          return;
        }
      } catch (_) {}

      // If existing file is different or partially downloaded
      existingBytes = await destFile.length();
      if (existingBytes > metadata.fileSize) {
        // Stale or different file: allocate non-colliding destination path
        final nameNoExt = p.basenameWithoutExtension(safeFileName);
        final ext = p.extension(safeFileName);
        safeFileName = '${nameNoExt}_${metadata.transferId.substring(0, 8)}$ext';
        destinationPath = p.join(downloadDir.path, safeFileName);
        destFile = File(destinationPath);
        existingBytes = 0;
      }
    }

    final transferInfo = FileTransferInfo(
      transferId: transferId,
      messageId: messageId,
      fileName: safeFileName,
      fileSize: metadata.fileSize,
      bytesTransferred: existingBytes,
      localPath: destinationPath,
      remoteIp: sender.ip,
      remotePort: sender.port,
      remotePublicKey: sender.publicKey,
      direction: TransferDirection.download,
      status: TransferStatus.transferring,
      sha256: metadata.sha256,
    );

    _transfers[transferId] = transferInfo;
    notifyListeners();

    _startDownloadStream(transferInfo);
  }

  Future<void> _startDownloadStream(FileTransferInfo info) async {
    final httpClient = HttpClient();
    _activeClients[info.transferId] = httpClient;

    final destFile = File(info.localPath);
    IOSink? sink;

    try {
      final uri = Uri.parse(
        'http://${info.remoteIp}:${info.remotePort}/api/file/download/${info.transferId}',
      );

      final request = await httpClient.getUrl(uri);

      // Support resumability via HTTP Range header
      if (info.bytesTransferred > 0) {
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${info.bytesTransferred}-',
        );
      }

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        info.status = TransferStatus.failed;
        notifyListeners();
        return;
      }

      sink = destFile.openWrite(
        mode: info.bytesTransferred > 0 ? FileMode.append : FileMode.write,
      );

      DateTime lastTime = DateTime.now();
      int bytesSinceLastTime = 0;

      await for (final chunk in response) {
        if (info.status == TransferStatus.paused) {
          break;
        }

        sink.add(chunk);
        info.bytesTransferred += chunk.length;
        bytesSinceLastTime += chunk.length;

        // Calculate speed every 500ms
        final now = DateTime.now();
        final elapsed = now.difference(lastTime).inMilliseconds;
        if (elapsed >= 500) {
          info.speedBytesPerSec = (bytesSinceLastTime / (elapsed / 1000.0));
          lastTime = now;
          bytesSinceLastTime = 0;
          notifyListeners();
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (info.status == TransferStatus.paused) {
        notifyListeners();
        return;
      }

      // Verify SHA-256 hash
      if (info.bytesTransferred >= info.fileSize) {
        final verifiedHash = await _calculateFileSha256(destFile);
        if (info.sha256.isNotEmpty && verifiedHash != info.sha256) {
          info.status = TransferStatus.failed;
        } else {
          info.status = TransferStatus.completed;
          await database.markFileCompleted(info.transferId, info.localPath);
        }
      } else {
        info.status = TransferStatus.paused;
      }
    } catch (e) {
      if (kDebugMode) print('Download error: $e');
      if (info.status != TransferStatus.paused) {
        info.status = TransferStatus.failed;
      }
    } finally {
      await sink?.close();
      httpClient.close(force: true);
      _activeClients.remove(info.transferId);
      notifyListeners();
    }
  }

  void pauseTransfer(String transferId) {
    final info = _transfers[transferId];
    if (info != null && info.status == TransferStatus.transferring) {
      info.status = TransferStatus.paused;
      _activeClients[transferId]?.close(force: true);
      _activeClients.remove(transferId);
      notifyListeners();
    }
  }

  void resumeTransfer(String transferId) {
    final info = _transfers[transferId];
    if (info != null && info.status == TransferStatus.paused) {
      info.status = TransferStatus.transferring;
      notifyListeners();
      _startDownloadStream(info);
    }
  }

  void cancelTransfer(String transferId) {
    final info = _transfers[transferId];
    if (info != null) {
      info.status = TransferStatus.failed;
      _activeClients[transferId]?.close(force: true);
      _activeClients.remove(transferId);
      server.unregisterSharedFile(transferId);
      notifyListeners();
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    if (customDownloadDirectory != null) {
      return customDownloadDirectory!;
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {}
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<String> _calculateFileSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  @override
  void dispose() {
    for (final client in _activeClients.values) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
    super.dispose();
  }
}
