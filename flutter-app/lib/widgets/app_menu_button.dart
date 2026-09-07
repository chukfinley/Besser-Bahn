import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/update_check_service.dart';

/// Overflow menu for the secondary destinations that no longer live in the
/// bottom navigation bar (Split-Ticket, Einstellungen, Debug-Log). Drop it into
/// the `actions:` of any core screen's AppBar.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: UpdateCheckService.available,
      builder: (context, update, _) => _menu(context, update),
    );
  }

  Widget _menu(BuildContext context, UpdateInfo? update) {
    return PopupMenuButton<String>(
      // A quiet dot on the icon when a newer version is out. No dialog, no
      // interruption: the rider finds it when they open the menu anyway.
      icon: update == null
          ? const Icon(Icons.more_vert)
          : Badge(
              backgroundColor: Theme.of(context).colorScheme.primary,
              smallSize: 8,
              child: const Icon(Icons.more_vert),
            ),
      tooltip: 'Mehr',
      onSelected: (route) => context.push(route),
      itemBuilder: (context) => [
        if (update != null)
          PopupMenuItem(
            value: '/settings',
            child: ListTile(
              leading: Icon(
                Icons.system_update,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('Version ${update.latestVersion} verfügbar'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: '/split',
          child: ListTile(
            leading: Icon(Icons.call_split),
            title: Text('Split-Ticket'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: '/settings',
          child: ListTile(
            leading: Icon(Icons.settings),
            title: Text('Einstellungen'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: '/debug-log',
          child: ListTile(
            leading: Icon(Icons.bug_report_outlined),
            title: Text('Debug-Log'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
