import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lan_telegram/core/crypto/crypto_service.dart';
import 'package:lan_telegram/core/database/app_database.dart';
import 'package:lan_telegram/core/database/models.dart';
import 'package:lan_telegram/core/network/p2p_client.dart';
import 'package:lan_telegram/core/network/p2p_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Host-Relay Group Chat: Host invites member, member sends message, host relays to group', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirHost = await Directory.systemTemp.createTemp('group_host_db');
    final tempDirMember = await Directory.systemTemp.createTemp('group_member_db');

    final crypto = CryptoService();
    await crypto.initialize();

    // 1. Initialize Host Node (Alice)
    final hostDb = AppDatabase();
    await hostDb.initialize(customDirectory: tempDirHost);
    final hostServer = P2pServer(
      requestedPort: 48010,
      deviceId: 'host-alice',
      deviceName: 'Alice (Host)',
      cryptoService: crypto,
    );
    final hostPort = await hostServer.start();
    final hostClient = P2pClient(
      deviceId: 'host-alice',
      deviceName: 'Alice (Host)',
      cryptoService: crypto,
    );

    // 2. Initialize Member Node (Bob)
    final memberDb = AppDatabase();
    await memberDb.initialize(customDirectory: tempDirMember);
    final memberServer = P2pServer(
      requestedPort: 48011,
      deviceId: 'member-bob',
      deviceName: 'Bob (Member)',
      cryptoService: crypto,
    );
    final memberPort = await memberServer.start();
    final memberClient = P2pClient(
      deviceId: 'member-bob',
      deviceName: 'Bob (Member)',
      cryptoService: crypto,
    );

    try {
      // 3. Setup Group Invite Listener on Bob
      final inviteCompleter = Completer<GroupChat>();
      memberServer.onGroupInvite = (group) {
        inviteCompleter.complete(group);
      };

      // 4. Host creates group and invites Bob
      final group = GroupChat(
        id: 'group-uuid-1',
        name: 'LAN Dev Team',
        hostId: 'host-alice',
        hostName: 'Alice (Host)',
        memberIds: ['host-alice', 'member-bob'],
        createdAt: DateTime.now(),
      );
      await hostDb.saveGroup(group);

      final bobPeer = Peer(
        id: 'member-bob',
        name: 'Bob (Member)',
        ip: '127.0.0.1',
        port: memberPort,
        publicKey: crypto.publicKeyBase64!,
        platform: 'windows',
        lastSeen: DateTime.now(),
      );

      final inviteSent = await hostClient.sendGroupInvite(peer: bobPeer, group: group);
      expect(inviteSent, isTrue);

      final receivedGroup = await inviteCompleter.future.timeout(const Duration(seconds: 5));
      expect(receivedGroup.id, equals('group-uuid-1'));
      expect(receivedGroup.name, equals('LAN Dev Team'));
      expect(receivedGroup.hostId, equals('host-alice'));
      await memberDb.saveGroup(receivedGroup);

      // 5. Bob sends a group message to Host
      final msgCompleter = Completer<ChatMessage>();
      hostServer.onGroupMessage = (msg, gId) {
        msgCompleter.complete(msg);
      };

      final hostPeer = Peer(
        id: 'host-alice',
        name: 'Alice (Host)',
        ip: '127.0.0.1',
        port: hostPort,
        publicKey: crypto.publicKeyBase64!,
        platform: 'windows',
        lastSeen: DateTime.now(),
      );

      final bobMessage = ChatMessage(
        id: 'msg-grp-1',
        chatId: group.id,
        senderId: 'member-bob',
        senderName: 'Bob (Member)',
        recipientId: group.id,
        content: 'Hey everyone in the LAN group!',
        timestamp: DateTime.now(),
        isGroup: true,
        groupId: group.id,
      );

      final msgSent = await memberClient.sendGroupMessage(
        hostPeer: hostPeer,
        group: group,
        message: bobMessage,
      );
      expect(msgSent, isTrue);

      final hostReceivedMsg = await msgCompleter.future.timeout(const Duration(seconds: 5));
      expect(hostReceivedMsg.content, equals('Hey everyone in the LAN group!'));
      expect(hostReceivedMsg.senderId, equals('member-bob'));
      expect(hostReceivedMsg.isGroup, isTrue);

      // Host relays to group members
      final relaySent = await hostClient.relayGroupMessage(
        memberPeer: bobPeer,
        group: group,
        message: hostReceivedMsg,
      );
      expect(relaySent, isTrue);
    } finally {
      await hostDb.close();
      await memberDb.close();
      await hostServer.stop();
      await memberServer.stop();
      hostClient.close();
      memberClient.close();
      try {
        await tempDirHost.delete(recursive: true);
      } catch (_) {}
      try {
        await tempDirMember.delete(recursive: true);
      } catch (_) {}
    }
  });
}
