import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../screens/register_object_screen.dart';

class ARPainter extends CustomPainter {
  final List<SavedObject> objects;
  final Position currentPosition;
  final double heading;
  final double tilt;
  final double fov;
  final Size screenSize;
  final double topPadding;

  ARPainter({
    required this.objects,
    required this.currentPosition,
    required this.heading,
    required this.tilt,
    required this.fov,
    required this.screenSize,
    this.topPadding = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    final markerOpacity = ((tilt - 0.2) / 0.4).clamp(0.0, 1.0);
    if (markerOpacity < 0.01) return;

    _drawCompassStrip(canvas, size);

    final halfFov = fov / 2;
    final centerY = screenSize.height * 0.38;

    for (final obj in objects) {
      final bearing = _calculateBearing(
        currentPosition.latitude, currentPosition.longitude,
        obj.latitude, obj.longitude,
      );
      final distance = Geolocator.distanceBetween(
        currentPosition.latitude, currentPosition.longitude,
        obj.latitude, obj.longitude,
      );
      var angleDiff = bearing - heading;
      angleDiff = _normalizeAngle(angleDiff);
      if (angleDiff.abs() > halfFov) continue;

      final typeEntry = _findTypeEntry(obj.type);
      final color = typeEntry?['color'] as Color? ?? Colors.white;
      final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

      final x = screenSize.width / 2 + (angleDiff / halfFov) * (screenSize.width / 2);

      _drawObjectMarkerForPosition(canvas, obj, x, centerY, distance, angleDiff, color, icon, markerOpacity);
    }
  }

  void _drawCompassStrip(Canvas canvas, Size size) {
    final stripTop = topPadding + 4;
    const stripH = 32.0;

    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.0)],
        stops: const [0.0, 0.08, 0.92, 1.0],
      ).createShader(Rect.fromLTWH(0, stripTop, size.width, stripH));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, stripTop, size.width, stripH),
        const Radius.circular(0),
      ),
      bgPaint,
    );

    final labels = {
      'N': 0, 'NE': 45, 'E': 90, 'SE': 135,
      'S': 180, 'SW': 225, 'O': 270, 'NW': 315,
    };

    for (final entry in labels.entries) {
      var d = entry.value - heading;
      d = _normalizeAngle(d);
      if (d.abs() > 90) continue;
      final x = size.width / 2 + (d / 90) * (size.width / 2);

      final isCardinal = ['N', 'E', 'S', 'O'].contains(entry.key);
      final tickH = isCardinal ? 18.0 : 10.0;
      final tickY = stripTop + stripH - tickH;

      canvas.drawLine(
        Offset(x, tickY),
        Offset(x, stripTop + stripH),
        Paint()
          ..color = isCardinal ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.25)
          ..strokeWidth = isCardinal ? 2 : 1,
      );

      _drawText(
        canvas, entry.key, x, stripTop + 2,
        fontSize: isCardinal ? 11 : 8,
        color: isCardinal ? Colors.white.withOpacity(0.85) : Colors.white.withOpacity(0.35),
        fontWeight: isCardinal ? FontWeight.bold : FontWeight.normal,
      );
    }

    final cx = size.width / 2;
    final cy = stripTop + stripH / 2;
    final diamondPaint = Paint()..color = Colors.white;
    final diamondPath = Path()
      ..moveTo(cx, cy - 6)
      ..lineTo(cx + 5, cy)
      ..lineTo(cx, cy + 6)
      ..lineTo(cx - 5, cy)
      ..close();
    canvas.drawPath(diamondPath, diamondPaint);

    canvas.drawLine(
      Offset(cx, stripTop + stripH - 18),
      Offset(cx, stripTop + stripH),
      Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1,
    );
  }

  void _drawObjectMarkerForPosition(Canvas canvas, SavedObject obj, double x, double centerY,
      double distance, double angleDiff, Color color, IconData icon, double opacity) {
    final absDiff = angleDiff.abs();
    const coreZone = 35.0;
    const fadeZone = 80.0;

    if (absDiff > fadeZone) {
      _drawEdgeDot(canvas, angleDiff, color, distance, opacity);
      return;
    }

    double markerOpacity;
    if (absDiff <= coreZone) {
      markerOpacity = opacity;
    } else {
      markerOpacity = opacity * (1.0 - ((absDiff - coreZone) / (fadeZone - coreZone)));
      markerOpacity = markerOpacity.clamp(0.3, 1.0);
    }

    final iconSize = _iconSizeForDistance(distance);
    final scaledIconSize = iconSize * (0.7 + 0.3 * markerOpacity);

    // Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.4 * markerOpacity), color.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: Offset(x, centerY), radius: scaledIconSize * 0.8));
    canvas.drawCircle(Offset(x, centerY), scaledIconSize * 0.8, glowPaint);

    // Pill
    final pillW = scaledIconSize + 16;
    final pillH = scaledIconSize + 10;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, centerY), width: pillW, height: pillH),
      const Radius.circular(16),
    );

    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.9 * markerOpacity),
          color.withOpacity(0.7 * markerOpacity),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(pillRect.outerRect);
    canvas.drawRRect(pillRect, bgPaint);

    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = Colors.white.withOpacity(0.5 * markerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    canvas.drawCircle(
      Offset(x, centerY),
      scaledIconSize / 2,
      Paint()..color = Colors.white.withOpacity(0.25 * markerOpacity),
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: scaledIconSize * 0.5,
          color: Colors.white.withOpacity(markerOpacity),
          fontFamily: icon.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(x - iconPainter.width / 2, centerY - iconPainter.height / 2),
    );

    final labelY = centerY + pillH / 2 + 4;

    final labelBgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, labelY + 14), width: pillW + 16, height: 32),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      labelBgRect,
      Paint()..color = Colors.black.withOpacity(0.7 * markerOpacity),
    );
    canvas.drawRRect(
      labelBgRect,
      Paint()
        ..color = Colors.white.withOpacity(0.15 * markerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    _drawText(
      canvas, obj.name, x, labelY + 4,
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white.withOpacity(0.95 * markerOpacity),
    );
    _drawText(
      canvas, _formatDistance(distance), x, labelY + 20,
      fontSize: 10,
      color: color.withOpacity(0.9 * markerOpacity),
    );
  }

  void _drawEdgeDot(Canvas canvas, double angleDiff, Color color, double distance, double opacity) {
    final x = angleDiff < 0 ? 16.0 : screenSize.width - 16.0;
    final centerY = screenSize.height * 0.38;

    canvas.drawCircle(
      Offset(x, centerY),
      6,
      Paint()..color = color.withOpacity(0.9 * opacity),
    );
    canvas.drawCircle(
      Offset(x, centerY),
      6,
      Paint()
        ..color = Colors.white.withOpacity(0.5 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final arrowIcon = angleDiff < 0 ? Icons.chevron_left : Icons.chevron_right;
    final arrowPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(arrowIcon.codePoint),
        style: TextStyle(
          fontSize: 18,
          color: color.withOpacity(0.9 * opacity),
          fontFamily: arrowIcon.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    arrowPainter.layout();
    arrowPainter.paint(
      canvas,
      Offset(x - arrowPainter.width / 2, centerY - arrowPainter.height / 2 - 12),
    );

    _drawText(
      canvas, _formatDistance(distance), x, centerY + 16,
      fontSize: 11,
      color: Colors.white.withOpacity(0.85 * opacity),
    );
  }

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, FontWeight fontWeight = FontWeight.normal, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          shadows: const [
            Shadow(blurRadius: 8, color: Color(0xCC000000)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  Map<String, dynamic>? _findTypeEntry(String type) {
    for (final t in objectTypes) {
      if (t['name'] == type) return t;
    }
    return null;
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);
    final dLon = _toRadians(lon2 - lon1);

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    final bearing = _toDegrees(math.atan2(y, x));
    return (bearing + 360) % 360;
  }

  double _normalizeAngle(double angle) {
    while (angle > 180) angle -= 360;
    while (angle < -180) angle += 360;
    return angle;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
  double _toDegrees(double radians) => radians * 180 / math.pi;

  double _iconSizeForDistance(double distance) {
    if (distance < 10) return 50;
    if (distance < 100) return 44;
    if (distance < 500) return 38;
    return 32;
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  bool shouldRepaint(ARPainter oldDelegate) {
    return (oldDelegate.heading - heading).abs() > 1.0 ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.objects != objects ||
        (oldDelegate.tilt - tilt).abs() > 0.02;
  }
}
