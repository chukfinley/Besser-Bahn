import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/settings_provider.dart';
import '../services/update_check_service.dart';

/// "Version X ist da" — the one place the update hint is rendered.
///
/// Sits at the top of the Suche tab (every rider passes it) and in the
/// settings. It never blocks: download, skip, or ignore it and it stays out of
/// the way until the next check.
class UpdateBanner extends ConsumerWidget {
  /// Compact form for the search tab: one line, no explanation paragraph.
  final bool compact;

  const UpdateBanner({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.updateCheckEnabled),
    );
    if (!enabled) return const SizedBox.shrink();

    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: UpdateCheckService.available,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        return compact ? _compact(context, info) : _card(context, info);
      },
    );
  }

  Widget _compact(BuildContext context, UpdateInfo info) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(context, info.apkUrl ?? info.releasePageUrl),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  Icons.system_update,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Version ${info.latestVersion} ist da — tippen zum Laden',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Nicht mehr anzeigen',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  onPressed: () => UpdateCheckService.skip(info.latestVersion),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, UpdateInfo info) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.system_update,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Version ${info.latestVersion} ist da',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        'Du hast ${info.currentVersion}. Das Update lädst du '
                        'auf GitHub herunter und installierst es über die alte '
                        'Version — deine Daten bleiben.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => UpdateCheckService.skip(info.latestVersion),
                  child: const Text('Überspringen'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () =>
                      _open(context, info.apkUrl ?? info.releasePageUrl),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Herunterladen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Konnte den Link nicht öffnen.')),
      );
    }
  }
}
