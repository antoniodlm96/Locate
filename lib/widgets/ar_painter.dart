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

  ARPainter({
    required this.objects,
    required this.currentPosition,
    required this.heading,
    required this.fov,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    for (final obj in objects) {
      _drawObjectMarker(canvas, obj);
    }
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
    if (angleDiff.abs() > halfFov + 5) return;

    final x = screenSize.width / 2 + (angleDiff / halfFov) * (screenSize.width / 2);
    if (x < -50 || x > screenSize.width + 50) return;

    final typeEntry = objectTypes.cast<Map<String, dynamic>?>().firstWhere(
      (t) => t?['name'] == obj.type,
      orElse: () => null,
    );

    final color = typeEntry?['color'] as Color? ?? Colors.white;
    final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

    final iconSize = _iconSizeForDistance(distance);
    final markerRect = Rect.fromCenter(
      center: Offset(x, screenSize.height * 0.4),
      width: iconSize,
      height: iconSize,
    );

    final bgPaint = Paint()..color = color.withOpacity(0.9);
    canvas.drawCircle(markerRect.center, iconSize / 2 + 4, bgPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconSize * 0.6,
          color: Colors.white,
          fontFamily: icon.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      markerRect.center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final label = obj.name;
    final distText = _formatDistance(distance);

    _drawText(canvas, label, x, screenSize.height * 0.4 + iconSize / 2 + 8,
        fontWeight: FontWeight.bold, fontSize: 13, color: color);

    _drawText(canvas, distText, x, screenSize.height * 0.4 + iconSize / 2 + 28,
        fontSize: 12, color: Colors.white70);
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
            Shadow(blurRadius: 4, color: Colors.black87),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
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
    if (distance < 10) return 56;
    if (distance < 100) return 48;
    if (distance < 500) return 40;
    return 32;
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  bool shouldRepaint(ARPainter oldDelegate) {
    return oldDelegate.heading != heading ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.objects != objects;
  }
}
