import 'package:flutter/material.dart';

import '../../models/atm.dart';
import '../../models/atm_status.dart';
import '../theme.dart';

/// A single map pin.
///
/// Two independent things are encoded, deliberately on two different visual
/// channels so they never compete:
///
///   colour + icon  = crowd-reported cash status
///   shape          = whether anyone has recorded which bank owns the machine
///
/// Solid pins are confirmed banks. Hollow pins - white centre, coloured ring -
/// are machines nobody has labelled yet, which is about half the dataset. They
/// still dispense cash, so they stay on the map at full prominence; they just
/// look different enough that a user filtering for their own bank can tell at a
/// glance which pins are a sure thing.
class AtmPin extends StatelessWidget {
  const AtmPin({
    super.key,
    required this.atm,
    required this.status,
    required this.onTap,
    this.emphasis = false,
    this.dimmed = false,
  });

  final Atm atm;
  final AtmStatus status;
  final VoidCallback onTap;

  /// The machine currently being routed to. Grown and ringed so it is findable
  /// among eighty identical neighbours.
  final bool emphasis;

  /// Everything that is not the destination, while navigating.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final trusted = status.isTrustworthy;
    // pinColour, not ink: a pin sits on the OSM raster, which is always a
    // light tile regardless of the app's theme.
    final colour =
        trusted ? status.status.pinColour : CashStatus.unknown.pinColour;
    final hollow = !atm.bankKnown;

    // Alpha is multiplied into each colour rather than wrapping the pin in an
    // Opacity widget: Opacity forces a saveLayer per pin, and there can be
    // eighty of them repainting on every pan frame.
    double fade(double a) => dimmed ? a * 0.45 : a;
    final size = emphasis ? 46.0 : 34.0;

    final icon = atm.kind == AtmKind.agent
        ? Icons.badge_rounded
        : trusted
            ? status.status.icon
            : hollow
                ? Icons.question_mark_rounded
                : Icons.local_atm_rounded;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: (hollow ? Colors.white : colour).withValues(alpha: fade(1)),
              shape: BoxShape.circle,
              border: Border.all(
                color: emphasis
                    ? kRouteInk
                    : (hollow ? colour : Colors.white)
                        .withValues(alpha: fade(1)),
                width: emphasis ? 4 : (hollow ? 3.5 : 2.5),
              ),
              boxShadow: dimmed
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(
                            alpha: emphasis ? 0.38 : 0.16),
                        blurRadius: emphasis ? 10 : 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Icon(
              icon,
              size: emphasis ? 22 : (hollow ? 15 : 17),
              color: (hollow ? colour : Colors.white)
                  .withValues(alpha: fade(1)),
            ),
          ),
          CustomPaint(
            size: Size(emphasis ? 13 : 10, emphasis ? 9 : 7),
            painter: _StemPainter(colour.withValues(alpha: fade(1))),
          ),
        ],
      ),
    );
  }
}

class _StemPainter extends CustomPainter {
  const _StemPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_StemPainter old) => old.colour != colour;
}
