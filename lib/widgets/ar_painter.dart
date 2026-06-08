import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../screens/register_object_screen.dart';

class ARPainter extends CustomPainter {
  final List<SavedObject> objects;
  final Position currentPosition;
  final double heading;
  final double fov;
  final Size screenSize;
  final double topPadding;

  ARPainter({
    required this.objects,
    required this.currentPosition,
    required this.heading,
    required this.fov,
    required this.screenSize,
    this.topPadding = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;
    _drawCompassStrip(canvas, size);
    for (final obj in objects) {
      _drawObjectMarker(canvas, obj);
    }
  }

  void _drawCompassStrip(Canvas canvas, Size size) {
    final stripTop = topPadding + 4;

    final bgPaint = Paint()
      ..color = Colors.black26;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, stripTop, size.width, 28),
        const Radius.circular(0),
      ),
      bgPaint,
    );

    final tickPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    final labels = {
      'N': 0, 'NE': 45, 'E': 90, 'SE': 135,
      'S': 180, 'SW': 225, 'O': 270, 'NW': 315,
    };
    for (final entry in labels.entries) {
      var d = entry.value - heading;
      d = _normalizeAngle(d);
      if (d.abs() > 90) continue;
      final x = size.width / 2 + (d / 90) * (size.width / 2);
      canvas.drawLine(Offset(x, stripTop + 20), Offset(x, stripTop + 28), tickPaint);
      _drawText(canvas, entry.key, x, stripTop + 3, fontSize: 9, color: Colors.white54);
    }

    final centerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5;
    canvas.drawLine(
      Offset(size.width / 2, stripTop + 18),
      Offset(size.width / 2, stripTop + 28),
      centerPaint,
    );
    canvas.drawLine(
      Offset(size.width / 2, stripTop + 14),
      Offset(size.width / 2, stripTop + 18),
      Paint()..color = Colors.white.withOpacity(0.4)..strokeWidth = 1,
    );
  }

  void _drawObjectMarker(Canvas canvas, SavedObject obj) {
    final bearing = _calculateBearing(
      currentPosition.latitude,
      currentPosition.longitude,
      obj.latitude,
      obj.longitude,
    );

    final distance = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      obj.latitude,
      obj.longitude,
    );

    var angleDiff = bearing - heading;
    angleDiff = _normalizeAngle(angleDiff);

    final halfFov = fov / 2;
    if (angleDiff.abs() > halfFov) return;

    final absDiff = angleDiff.abs();
    final coreZone = 35.0;
    final fadeZone = 80.0;

    final typeEntry = _findTypeEntry(obj.type);
    final color = typeEntry?['color'] as Color? ?? Colors.white;
    final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

    final x = screenSize.width / 2 + (angleDiff / halfFov) * (screenSize.width / 2);
    final centerY = screenSize.height * 0.38;

    if (absDiff > fadeZone) {
      _drawEdgeDot(canvas, angleDiff, color, distance);
      return;
    }

    double opacity;
    if (absDiff <= coreZone) {
      opacity = 1.0;
    } else {
      opacity = 1.0 - ((absDiff - coreZone) / (fadeZone - coreZone));
      opacity = opacity.clamp(0.15, 1.0);
    }

    final iconSize = _iconSizeForDistance(distance);
    final scaledIconSize = iconSize * (0.7 + 0.3 * opacity);

    final bgPaint = Paint()..color = color.withOpacity(0.65 * opacity);
    canvas.drawCircle(
      Offset(x, centerY),
      scaledIconSize / 2 + 5,
      bgPaint,
    );

    canvas.drawCircle(
      Offset(x, centerY),
      scaledIconSize / 2 + 5,
      Paint()
        ..color = Colors.white.withOpacity(0.2 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: scaledIconSize * 0.55,
          color: Colors.white.withOpacity(opacity),
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

    final textOpacity = opacity;
    final labelY = centerY + scaledIconSize / 2 + 8;
    _drawText(
      canvas, obj.name, x, labelY,
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: color.withOpacity(0.9 * textOpacity),
    );
    _drawText(
      canvas, _formatDistance(distance), x, labelY + 18,
      fontSize: 12,
      color: Colors.white.withOpacity(0.7 * textOpacity),
    );
  }

  void _drawEdgeDot(Canvas canvas, double angleDiff, Color color, double distance) {
    final x = angleDiff < 0 ? 10.0 : screenSize.width - 10.0;
    final centerY = screenSize.height * 0.38;

    canvas.drawCircle(
      Offset(x, centerY),
      6,
      Paint()..color = color.withOpacity(0.7),
    );
    canvas.drawCircle(
      Offset(x, centerY),
      6,
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final arrowIcon = angleDiff < 0 ? Icons.chevron_left : Icons.chevron_right;
    final arrowPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(arrowIcon.codePoint),
        style: TextStyle(
          fontSize: 16,
          color: color,
          fontFamily: arrowIcon.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    arrowPainter.layout();
    arrowPainter.paint(
      canvas,
      Offset(x - arrowPainter.width / 2, centerY - arrowPainter.height / 2 - 10),
    );

    _drawText(
      canvas, _formatDistance(distance), x, centerY + 14,
      fontSize: 10,
      color: color.withOpacity(0.8),
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
            Shadow(blurRadius: 5, color: Color(0xAA000000)),
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
        oldDelegate.objects != objects;
  }
}
