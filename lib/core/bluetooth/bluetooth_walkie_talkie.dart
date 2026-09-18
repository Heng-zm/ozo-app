import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'ble_constants.dart';
import 'ble_packet.dart';
import 'ble_service.dart';

enum WalkieTalkieState {
  idle,
  recording,
  transmitting,
  playing,
}

class BluetoothWalkieTalkie {
  static final BluetoothWalkieTalkie _instance = BluetoothWalkieTalkie._internal();
  factory BluetoothWalkieTalkie() => _instance;
  BluetoothWalkieTalkie._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  WalkieTalkieState _state = WalkieTalkieState.idle;
  WalkieTalkieState get state => _state;

  final StreamController<WalkieTalkieState> _stateController = StreamController<WalkieTalkieState>.broadcast();
  Stream<WalkieTalkieState> get stateStream => _stateController.stream;

  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Timer? _amplitudeTimer;
  String? _currentRecordingPath;
  StreamSubscription<BlePacket>? _blePacketSub;

  void init(BleService bleService) {
    _blePacketSub?.cancel();
    _blePacketSub = bleService.onPacketReceived.listen((packet) {
      if (packet.packetType == BleConstants.packetTypeVoice) {
        handleIncomingVoicePacket(packet.payload);
      }
    });

    _player.onPlayerComplete.listen((_) {
      _setState(WalkieTalkieState.idle);
    });
  }

  void _setState(WalkieTalkieState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  /// Start PTT recording
  Future<bool> startTalking() async {
    if (_state != WalkieTalkieState.idle) return false;

    try {
      if (!await _recorder.hasPermission()) {
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = p.join(tempDir.path, fileName);

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
        ),
        path: _currentRecordingPath!,
      );

      _setState(WalkieTalkieState.recording);

      _amplitudeTimer?.cancel();
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        try {
          final amp = await _recorder.getAmplitude();
          final db = amp.current.clamp(-60.0, 0.0);
          final norm = ((db + 60.0) / 60.0).clamp(0.05, 1.0);
          _amplitudeController.add(norm);
        } catch (_) {}
      });

      return true;
    } catch (e) {
      debugPrint('[WalkieTalkie] startTalking error: $e');
      _setState(WalkieTalkieState.idle);
      return false;
    }
  }

  /// Release PTT button, finalize audio chunk, and broadcast via BLE
  Future<bool> stopTalkingAndTransmit(BleService bleService, BlePeer? targetPeer) async {
    if (_state != WalkieTalkieState.recording) return false;

    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    try {
      final path = await _recorder.stop();
      if (path == null) {
        _setState(WalkieTalkieState.idle);
        return false;
      }

      final file = File(path);
      if (!await file.exists()) {
        _setState(WalkieTalkieState.idle);
        return false;
      }

      final audioBytes = await file.readAsBytes();
      if (audioBytes.isEmpty) {
        _setState(WalkieTalkieState.idle);
        return false;
      }

      _setState(WalkieTalkieState.transmitting);

      bool success = false;
      if (targetPeer?.device != null) {
        success = await bleService.sendData(
          targetPeer!.device!,
          BleConstants.packetTypeVoice,
          audioBytes,
          targetCharacteristicUuid: BleConstants.voiceCharacteristicUuid,
        );
      }

      // Cleanup local temp file
      try {
        await file.delete();
      } catch (_) {}

      _setState(WalkieTalkieState.idle);
      return success;
    } catch (e) {
      debugPrint('[WalkieTalkie] stopTalkingAndTransmit error: $e');
      _setState(WalkieTalkieState.idle);
      return false;
    }
  }

  /// Cancel current recording without transmitting
  Future<void> cancelTalking() async {
    if (_state != WalkieTalkieState.recording) return;

    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    try {
      final path = await _recorder.stop();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}

    _setState(WalkieTalkieState.idle);
  }

  /// Handle incoming voice packet and immediately play back via AudioPlayer
  Future<void> handleIncomingVoicePacket(Uint8List audioBytes) async {
    if (audioBytes.isEmpty) return;

    try {
      _setState(WalkieTalkieState.playing);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'rx_ptt_${DateTime.now().millisecondsSinceEpoch}.m4a'));
      await tempFile.writeAsBytes(audioBytes);

      await _player.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      debugPrint('[WalkieTalkie] handleIncomingVoicePacket error: $e');
      _setState(WalkieTalkieState.idle);
    }
  }

  void dispose() {
    _blePacketSub?.cancel();
    _amplitudeTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _stateController.close();
    _amplitudeController.close();
  }
}
