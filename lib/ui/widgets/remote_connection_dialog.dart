import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/database/models.dart';
import '../../providers/chat_provider.dart';

/// Modal dialog for Remote P2P connections (Cloudflare Tunnel, QR code, and manual IP/Domain)
class RemoteConnectionDialog extends StatefulWidget {
  const RemoteConnectionDialog({super.key});

  @override
  State<RemoteConnectionDialog> createState() => _RemoteConnectionDialogState();
}

class _RemoteConnectionDialogState extends State<RemoteConnectionDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _cfUrlController = TextEditingController();
  final TextEditingController _connectInputController = TextEditingController();
  bool _isConnecting = false;
  String? _connectError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cfUrlController.dispose();
    _connectInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final theme = Theme.of(context);

    // Build the connection link
    final tunnelHost = _cfUrlController.text.trim().replaceAll('https://', '').replaceAll('http://', '').split('/').first;
    final hasTunnel = tunnelHost.isNotEmpty;

    final link = PeerConnectionLink(
      id: provider.deviceId,
      name: provider.deviceName,
      host: hasTunnel ? tunnelHost : '127.0.0.1',
      port: hasTunnel ? 443 : provider.serverPort,
      publicKey: provider.cryptoService.publicKeyBase64 ?? '',
      platform: provider.platform,
      isSecure: hasTunnel,
    );

    final linkString = link.toUriString();

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync_rounded, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remote P2P Connection',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Connect across different networks via Cloudflare Tunnel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.qr_code_rounded), text: 'Share My Link'),
                Tab(icon: Icon(Icons.add_link_rounded), text: 'Connect to Peer'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Share Link & QR
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: QrImageView(
                              data: linkString,
                              version: QrVersions.auto,
                              size: 160.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _cfUrlController,
                          decoration: InputDecoration(
                            labelText: 'Cloudflare Tunnel URL (Optional)',
                            hintText: 'e.g. peaceful-tiger.trycloudflare.com',
                            prefixIcon: const Icon(Icons.link_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            suffixIcon: _cfUrlController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _cfUrlController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      linkString,
                                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: linkString));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('App connection link copied to clipboard!'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 16),
                                    label: const Text('App Link'),
                                  ),
                                ],
                              ),
                              if (hasTunnel) ...[
                                const Divider(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'https://$tunnelHost/',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                          Text(
                                            'Public Web Connect Page & REST API',
                                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: 'https://$tunnelHost/'));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Public Web / API link copied!'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.public_rounded, size: 16),
                                      label: const Text('Web Link'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.api_rounded, size: 16, color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Public User Connect API is Active',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Anyone opening your link in a web browser can view your node, test GET /api/info, and connect directly. Run "cloudflared tunnel --url http://127.0.0.1:${provider.serverPort}" to get a public HTTPS address.',
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: Connect to Remote Peer
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Enter Remote Connection Info',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Paste an ozo:// link, Cloudflare domain, or IP:Port from your peer.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _connectInputController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Paste ozo://connect?... or https://xyz.trycloudflare.com',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        if (_connectError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _connectError!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ],
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _isConnecting
                              ? null
                              : () async {
                                  final input = _connectInputController.text.trim();
                                  if (input.isEmpty) return;

                                  setState(() {
                                    _isConnecting = true;
                                    _connectError = null;
                                  });

                                  final navigator = Navigator.of(context);
                                  final messenger = ScaffoldMessenger.of(context);

                                  final success = await provider.connectToRemotePeer(input);
                                  if (!mounted) return;
                                  setState(() {
                                    _isConnecting = false;
                                  });
                                  if (success) {
                                    navigator.pop();
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Connected to remote peer!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } else {
                                    setState(() {
                                      _connectError = 'Could not establish connection to remote peer.';
                                    });
                                  }
                                },
                          icon: _isConnecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(_isConnecting ? 'Connecting...' : 'Connect to Peer'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
