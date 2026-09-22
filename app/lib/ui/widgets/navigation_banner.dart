import 'package:flutter/material.dart';

import '../../l10n/bank_names.dart';
import '../../l10n/strings.dart';
import '../../models/atm.dart';
import '../../models/atm_status.dart';
import '../../services/routing_service.dart';
import '../theme.dart';

/// The bar shown across the bottom of the map while routing to a machine.
///
/// It carries three things and nothing else: where you are going, how far is
/// left, and how to stop. This is route *following*, not turn-by-turn - there
/// are no spoken instructions and no rerouting, because both need a paid
/// routing service to do properly. Saying so plainly in the UI (via the
/// straight-line notice) is better than implying a capability that is not
/// there.
class NavigationBanner extends StatelessWidget {
  const NavigationBanner({
    super.key,
    required this.target,
    required this.route,
    required this.remainingMetres,
    required this.loading,
    required this.onStop,
  });

  final Atm target;
  final AtmRoute? route;
  final double? remainingMetres;
  final bool loading;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    final title = target.bankLabel(s, short: true);

    final arrived = remainingMetres != null && remainingMetres! <= 25;
    final arrivedInk = CashStatus.hasCash.ink(theme.brightness);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: arrived
                            ? CashStatus.hasCash.wash(theme.brightness)
                            : theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        arrived
                            ? Icons.check_circle_rounded
                            : Icons.navigation_rounded,
                        color:
                            arrived ? arrivedInk : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(s),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: arrived
                                  ? arrivedInk
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: arrived ? FontWeight.w700 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: onStop,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: s.stopRoute,
                    ),
                  ],
                ),
                // Be explicit when the line on the map is not a road route.
                if (route != null && route!.isApproximate) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.straightLineRoute,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(Strings s) {
    if (loading) return s.findingRoute;
    if (remainingMetres == null) return s.findingRoute;
    if (remainingMetres! <= 25) return s.arrived;

    final distance = formatDistance(remainingMetres!, s);
    // Walking pace, same assumption the straight-line estimate uses.
    final minutes = (remainingMetres! / 1.35 / 60).ceil();
    return '$distance · ${s.minutesAway(minutes)}';
  }
}
