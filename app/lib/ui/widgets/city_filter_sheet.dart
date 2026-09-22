import 'package:flutter/material.dart';

import '../../data/cities.dart';
import '../../l10n/strings.dart';

/// Single-select city picker.
///
/// Single rather than multi because the question people actually ask is "NBI in
/// Sulaymaniyah", never "NBI in Sulaymaniyah or Zakho". The first option clears
/// the filter and returns to distance-from-me ordering.
class CityFilterSheet extends StatelessWidget {
  const CityFilterSheet({
    super.key,
    required this.cities,
    required this.selected,
  });

  final List<({String id, int count})> cities;

  /// null means "around me", with no city restriction.
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    String name(String id) {
      final display = cityDisplay(id);
      return switch (s.lang) {
        AppLang.ckb => display.ckb,
        AppLang.ar => display.ar,
        AppLang.en => display.en,
      };
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s.chooseCity,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Expanded(
            // A tap anywhere in the group closes the sheet with that choice,
            // so picking a city is one tap rather than pick-then-confirm.
            child: RadioGroup<String?>(
              groupValue: selected,
              onChanged: (value) =>
                  Navigator.of(context).pop(CityChoice(value)),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  RadioListTile<String?>(
                    value: null,
                    title: Text(s.aroundMe),
                    secondary: const Icon(Icons.my_location),
                  ),
                  const Divider(height: 1),
                  for (final city in cities)
                    RadioListTile<String?>(
                      value: city.id,
                      title: Text(name(city.id)),
                      secondary: Text(
                        '${city.count}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the sheet returns.
///
/// Wrapping the result distinguishes "the user chose Around me" from "the user
/// dismissed the sheet" - both of which would otherwise arrive as a bare null.
class CityChoice {
  const CityChoice(this.cityId);
  const CityChoice.aroundMe() : cityId = null;

  /// null means no city restriction.
  final String? cityId;
}
