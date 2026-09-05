import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chunked byte slicing and SHA-256 integrity verification', () async {
    final tempDir = await Directory.systemTemp.createTemp('lan_tg_test');
    final sourceFile = File('${tempDir.path}/source.bin');
    final targetFile = File('${tempDir.path}/target.bin');

    try {
      // 1. Generate a 2.5 MB test file
      final totalSize = (2.5 * 1024 * 1024).toInt();
      final buffer = Uint8List(totalSize);
      for (int i = 0; i < totalSize; i++) {
        buffer[i] = i % 256;
      }
      await sourceFile.writeAsBytes(buffer);

      // 2. Compute original SHA-256
      final originalHash = (await sha256.bind(sourceFile.openRead()).first).toString();
      expect(originalHash, isNotEmpty);

      // 3. Simulate chunked transfer with 512 KB chunks
      const chunkSize = 512 * 1024;
      final rafSource = await sourceFile.open(mode: FileMode.read);
      final rafTarget = await targetFile.open(mode: FileMode.write);

      int bytesRead = 0;
      while (bytesRead < totalSize) {
        final toRead = (totalSize - bytesRead) > chunkSize ? chunkSize : (totalSize - bytesRead);
        final chunk = await rafSource.read(toRead);
        await rafTarget.writeFrom(chunk);
        bytesRead += chunk.length;
      }

      await rafSource.close();
      await rafTarget.close();

      // 4. Verify target file size and SHA-256 checksum match
      expect(await targetFile.length(), equals(totalSize));
      final reconstructedHash = (await sha256.bind(targetFile.openRead()).first).toString();
      expect(reconstructedHash, equals(originalHash));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
