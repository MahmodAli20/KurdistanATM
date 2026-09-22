import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

typedef BankOption = ({String id, String nameEn, String nameCkb, int count});

/// Bank picker.
///
/// The filter itself never removes machines whose owner is unrecorded - just
/// under half the dataset - because one of them may well be the bank you hold
/// a card for.
///
/// What they get is *demoted*, not dropped, and differently per screen: the
/// Nearby list sorts them below a "bank not recorded" heading, while the map
/// hides them behind a toggle with an always-visible count, because a hundred
/// identical hollow pins bury the handful of real matches. Neither screen ever
/// silently shrinks the result set without saying so.
class BankFilterSheet extends StatefulWidget {
  const BankFilterSheet({
    super.key,
    required this.banks,
    required this.selected,
  });

  final List<BankOption> banks;
  final Set<String> selected;

  @override
  State<BankFilterSheet> createState() => _BankFilterSheetState();
}

class _BankFilterSheetState extends State<BankFilterSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.filterByBank,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: Text(s.clear),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                CheckboxListTile(
                  value: _selected.isEmpty,
                  onChanged: (_) => setState(_selected.clear),
                  title: Text(s.allBanks),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const Divider(height: 1),
                for (final bank in widget.banks)
                  CheckboxListTile(
                    value: _selected.contains(bank.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(bank.id);
                      } else {
                        _selected.remove(bank.id);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      s.lang == AppLang.ckb ? bank.nameCkb : bank.nameEn,
                    ),
                    secondary: Text(
                      '${bank.count}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: Text(s.done),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
