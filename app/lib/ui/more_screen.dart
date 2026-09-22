import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/atm_repository.dart';
import '../data/status_repository.dart';
import '../l10n/strings.dart';
import '../models/atm.dart';

/// Language, an explanation of how the crowd reporting works, and credits.
///
/// Folded into one tab rather than given a "Support" tab of its own: this is a
/// free community project with nobody to escalate to, and an empty support
/// screen is worse than no support screen.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.atms, required this.status});

  final AtmRepository atms;
  final StatusRepository status;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final change = LangScope.changerOf(context);

    final machines =
        atms.all.where((a) => a.kind == AtmKind.atm).length;
    final cities = atms.all.map((a) => a.city).toSet().length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            s.more,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),

          _SectionTitle(s.language),
          const SizedBox(height: 8),
          SegmentedButton<AppLang>(
            segments: [
              for (final lang in AppLang.values)
                ButtonSegment(value: lang, label: Text(Strings(lang).langName)),
            ],
            selected: {s.lang},
            onSelectionChanged: (selection) =>
                change?.call(selection.first),
            showSelectedIcon: false,
          ),

          const SizedBox(height: 28),
          _InfoCard(title: s.howItWorks, body: s.howItWorksBody),
          const SizedBox(height: 12),
          _InfoCard(title: s.privacy, body: s.privacyBody),

          const SizedBox(height: 28),
          _SectionTitle(s.dataSources),
          const SizedBox(height: 8),
          _StatRow(label: s.totalMachines, value: '$machines'),
          _StatRow(label: s.citiesCovered, value: '$cities'),
          const SizedBox(height: 10),
          Text(
            s.dataCredit,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 28),
          Center(
            child: Text(
              s.freeForever,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 20),
          const _DeveloperCard(),

          const SizedBox(height: 12),
          _AnonymousIdCard(id: status.anonymousId),

          const SizedBox(height: 12),
          // Play expects the policy to be reachable inside the app, not only
          // from the store listing - and the deletion instructions above are
          // useless without somewhere to send them.
          _LinkRow(
            icon: Icons.privacy_tip_outlined,
            label: s.privacyPolicy,
            url: 'https://mahmodali20.github.io/KurdistanATM/privacy.html',
            lang: s.lang.name,
          ),
          _LinkRow(
            icon: Icons.delete_outline_rounded,
            label: s.deleteMyData,
            url: 'https://mahmodali20.github.io/KurdistanATM/delete-data.html',
            lang: s.lang.name,
          ),
        ],
      ),
    );
  }
}

/// The only handle a user has on their own data.
///
/// There are no accounts, so this random per-install string is the only thing
/// linking a person to the reports they submitted. Without showing it, the
/// "request deletion" route promised by the privacy policy would be impossible
/// to actually use - the user would have nothing to quote.
class _AnonymousIdCard extends StatelessWidget {
  const _AnonymousIdCard({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    if (id.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.anonymousIdLabel,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            s.anonymousIdNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: id));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.copied)),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  // An opaque identifier is a left-to-right run; inside a
                  // Sorani page its characters would otherwise be reordered
                  // and the user would copy out something they cannot match.
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        id,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_rounded,
                      size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who made the app, and how to reach him.
///
/// The name and the phone number are both left-to-right runs sitting inside a
/// right-to-left page, so each is wrapped in its own [Directionality]. Without
/// that, a leading zero or a trailing digit migrates to the wrong end of the
/// number in Sorani and Arabic - and a phone number that renders wrong is
/// worse than no phone number.
class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri);
    } catch (_) {
      // A device with no dialler - a tablet, an emulator - should not crash
      // the settings screen. The number is on screen to read either way.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline_rounded,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '${s.developer}:',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  s.developerName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.reportAnIssue,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          // Tappable: someone who has found a broken ATM listing should be one
          // tap from reporting it, not copying digits by hand.
          Material(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _call(s.contactPhone),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_rounded,
                        size: 18, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        s.contactPhone,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row that opens one of the policy pages in the browser, in the language
/// the app is currently using - the site reads the `lang` query parameter.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.lang,
  });

  final IconData icon;
  final String label;
  final String url;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            try {
              await launchUrl(
                Uri.parse('$url?lang=$lang'),
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {
              // No browser available; nothing useful to say.
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleSmall),
                ),
                const Icon(Icons.open_in_new_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium, softWrap: true),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
