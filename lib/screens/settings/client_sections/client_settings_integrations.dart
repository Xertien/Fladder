import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/widgets/settings_label_divider.dart';
import 'package:fladder/screens/settings/widgets/settings_list_group.dart';
import 'package:fladder/util/localization_helper.dart';

List<Widget> buildClientSettingsIntegrations(BuildContext context, WidgetRef ref) {
  return settingsListGroup(
    context,
    SettingsLabelDivider(label: context.localized.integrations),
    [
      SettingsListTile(
        label: Text(context.localized.discordRichPresenceTitle),
        subLabel: Text(context.localized.discordRichPresenceDesc),
        onTap: () => ref
            .read(clientSettingsProvider.notifier)
            .setDiscordRichPresence(!ref.read(clientSettingsProvider.select((value) => value.discordRichPresence))),
        trailing: Switch(
          value: ref.watch(clientSettingsProvider.select((value) => value.discordRichPresence)),
          onChanged: (value) => ref.read(clientSettingsProvider.notifier).setDiscordRichPresence(value),
        ),
      ),
    ],
  );
}
