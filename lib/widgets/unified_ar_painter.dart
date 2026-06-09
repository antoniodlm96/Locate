import 'dart:math' as math;
import 'dart:ui' show Picture, PictureRecorder, Canvas;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../models/object_group.dart';
import '../screens/register_object_screen.dart';
import '../screens/ar_view_screen.dart';

class UnifiedARPainter extends CustomPainter {
  final List<ObjectWithDistance> objects;
  final List<ObjectGroup> groups;
  final Position currentPosition;
  final List<SavedObject> rawObjects;
  final double heading;
  final double tilt;
  final double fov;
  final Size screenSize;
  final double topPadding;

  UnifiedARPainter({
    required this.objects,
    required this.groups,
    required this.currentPosition,
    required this.rawObjects,
    required this.heading,
    required this.tilt,
    required this.fov,
    required this.screenSize,
    this.topPadding = 0,
  });

  // Cache for the compass picture — regenerated when size, heading, or tilt changes significantly
  static Picture? _cachedCompass;
  static Size _cachedSize = Size.zero;
  static double _cachedHeading = -999;
  static double _cachedTilt = -999;

  static Picture? buildCompassPicture(Size size, double heading, double tilt) {
    final sizeDiff = (size.width - _cachedSize.width).abs() + (size.height - _cachedSize.height).abs();
    final tiltDiff = (tilt - _cachedTilt).abs();
    final keyChanged = sizeDiff > 1 || (heading - _cachedHeading).abs() > 3 || tiltDiff > 0.03;
    if (!keyChanged && _cachedCompass != null) return _cachedCompass;

    _cachedSize = size;
    _cachedHeading = heading;
    _cachedTilt = tilt;

    final t = tilt.clamp(0.0, 1.0);
    final yScale = 0.35 + 0.65 * math.cos(t * math.pi / 2);
    final zoom = 1.0 + 0.25 * t;
    final radius = math.min(size.width, size.height) * 0.42 * zoom;
    final centerX = size.width / 2;
    final centerY = _lerp(size.height * 0.45, size.height * 0.82, t);

    final recorder = PictureRecorder();
    final c = Canvas(recorder);

    // Rings
    const nSteps = 64;
    for (int ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final path = Path();
      for (int i = 0; i <= nSteps; i++) {
        final angle = 2 * math.pi * i / nSteps;
        final px = centerX + r * math.sin(angle);
        final py = centerY - r * math.cos(angle) * yScale;
        (i == 0 ? path.moveTo : path.lineTo)(px, py);
      }
      path.close();
      final alpha = (0.55 - ring * 0.09).clamp(0.0, 1.0);
      c.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - ring * 0.3);
    }

    // Grid lines
    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 6;
      c.drawLine(
        Offset(centerX, centerY),
        Offset(centerX + radius * math.sin(angle), centerY - radius * math.cos(angle) * yScale),
        Paint()..color = Colors.white.withOpacity(0.12)..strokeWidth = 1.0,
      );
    }

    // Cardinal points
    final cardinals = <String, double>{
      'N': -heading, 'E': 90 - heading, 'S': 180 - heading, 'O': 270 - heading,
    };
    for (final entry in cardinals.entries) {
      final angleRad = entry.value * math.pi / 180;
      final lx = centerX + (radius + 24) * math.sin(angleRad);
      final ly = centerY - (radius + 24) * math.cos(angleRad) * yScale;
      final isNorth = entry.key == 'N';
      _drawTextOnCanvas(c, entry.key, lx, ly,
        fontSize: isNorth ? 24 : 18,
        fontWeight: FontWeight.bold,
        color: Colors.white.withOpacity(isNorth ? 1.0 : 0.85),
      );
    }

    // Direction arrow
    final arrowP = Offset(centerX, centerY - radius * yScale - 18);
    c.drawPath(
      Path()
        ..moveTo(arrowP.dx, arrowP.dy)
        ..lineTo(arrowP.dx - 10, arrowP.dy + 20)
        ..lineTo(arrowP.dx + 10, arrowP.dy + 20)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.85),
    );
    c.drawCircle(Offset(centerX, centerY), 3.5, Paint()..color = Colors.white.withOpacity(0.85));

    final picture = recorder.endRecording();
    _cachedCompass = picture;
    _cachedSize = size;
    _cachedHeading = heading;
    return picture;
  }

  static void _drawTextOnCanvas(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, FontWeight fontWeight = FontWeight.normal, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color, fontSize: fontSize, fontWeight: fontWeight,
          shadows: const [
            Shadow(blurRadius: 10, color: Color(0xEE000000)),
            Shadow(blurRadius: 3, color: Color(0xCC000000)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final t = tilt.clamp(0.0, 1.0);

    // === Camera AR markers (front layer) ===
    // These fade in as phone tilts — from ground radar painter perspective
    final markerOpacity = ((t - 0.2) / 0.4).clamp(0.0, 1.0);

    if (markerOpacity > 0.01 && rawObjects.isNotEmpty) {
      _drawARMarkers(canvas, size, markerOpacity);
    }

    // === Ground radar (back layer) ===
    // Includes background, compass, objects, groups
    _drawGroundRadar(canvas, size);
  }

  void _drawGroundRadar(Canvas canvas, Size size) {
    final t = tilt.clamp(0.0, 1.0);
    final yScale = 0.35 + 0.65 * math.cos(t * math.pi / 2);
    final centerX = size.width / 2;
    final centerY = _lerp(size.height * 0.45, size.height * 0.82, t);
    final zoom = 1.0 + 0.25 * t;
    final radius = math.min(size.width, size.height) * 0.42 * zoom;

    // Background
    final bgFade = ((t - 0.50) / 0.25).clamp(0.0, 1.0);
    final bgOpacity = 1.0 - bgFade;
    if (bgOpacity > 0.99) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF0B0E1A),
      );
    } else if (bgOpacity > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0B0E1A).withOpacity(bgOpacity),
            const Color(0xFF0B0E1A).withOpacity(bgOpacity * 0.9),
            const Color(0xFF0B0E1A).withOpacity(bgOpacity * 0.7),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // === Draw cached compass (static elements) ===
    final compassPic = buildCompassPicture(size, heading, tilt);
    if (compassPic != null) {
      canvas.drawPicture(compassPic);
    }

    // === Dynamic elements (objects + groups) ===
    if (objects.isEmpty) {
      _drawText(canvas, 'Sin objetos cerca', centerX, centerY + 35,
          fontSize: 17, color: Colors.white.withOpacity(0.5));
      return;
    }

    final maxDist = objects.map((o) => o.distance).reduce(math.max);
    final radarMax = math.max(50.0, math.min(maxDist * 1.3, 500.0));
    final radialExtent = radius * 0.88;

    // Groups: always polar
    final Map<int, Offset> groupPositions = {};
    for (final group in groups) {
      for (final m in group.sortedObjects) {
        final id = m.id;
        if (id == null) continue;
        final obj = objects.cast<ObjectWithDistance?>().firstWhere(
          (o) => o?.object.id == id,
          orElse: () => null,
        );
        if (obj == null) continue;
        final bearingDiff = obj.bearing - heading;
        final angleRad = bearingDiff * math.pi / 180;
        final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
        final objR = distFactor * radialExtent;
        groupPositions[id] = Offset(
          centerX + objR * math.sin(angleRad),
          centerY - objR * math.cos(angleRad) * yScale,
        );
      }
    }

    // Render groups
    for (final group in groups) {
      final members = group.sortedObjects;
      if (members.length < 2) continue;

      final pts = <Offset>[];
      for (final m in members) {
        final id = m.id;
        if (id == null) continue;
        final pos = groupPositions[id];
        if (pos != null) pts.add(pos);
      }
      if (pts.length < 2) continue;

      final baseColor = group.type == 'area' ? Colors.green : Colors.cyan;

      if (group.type == 'area' && pts.length >= 3) {
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
        path.close();
        canvas.drawPath(path, Paint()
          ..shader = RadialGradient(
            colors: [baseColor.withOpacity(0.25), baseColor.withOpacity(0.05)],
          ).createShader(Rect.fromPoints(pts[0], pts[pts.length ~/ 2]).inflate(50)));
        canvas.drawPath(path, Paint()
          ..color = baseColor.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);

        if (t > 0.3 && _isPointInsidePolygon(Offset(centerX, centerY), pts)) {
          _drawText(canvas, '● DENTRO DEL ÁREA', centerX, centerY - 28,
              fontSize: 13, fontWeight: FontWeight.bold, color: baseColor.withOpacity(1.0));
        }
      } else {
        for (int i = 0; i < pts.length - 1; i++) {
          canvas.drawLine(pts[i], pts[i + 1], Paint()
            ..color = baseColor.withOpacity(0.75)
            ..strokeWidth = 4);
        }
      }

      double cx = 0, cy = 0;
      for (final p in pts) { cx += p.dx; cy += p.dy; }
      _drawText(canvas, group.name, cx / pts.length, cy / pts.length,
          fontSize: 12, fontWeight: FontWeight.bold, color: baseColor.withOpacity(1.0));
    }

    // Objects
    // Visibility cone: 360° at tilt=0 (full circle), 180° at tilt=1 (front hemisphere)
    final visibleCone = 180.0 + (1.0 - t) * 180.0;

    for (final obj in objects) {
      final bearingDiff = obj.bearing - heading;
      final absDiff = bearingDiff.abs();
      final angleRad = bearingDiff * math.pi / 180;

      final excess = (absDiff - visibleCone * 0.5) / (visibleCone * 0.5);
      final fade = (1.0 - excess * 2).clamp(0.0, 1.0);
      if (fade < 0.01) continue;

      final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
      final objR = distFactor * radialExtent;

      final x = centerX + objR * math.sin(angleRad);
      final y = centerY - objR * math.cos(angleRad) * yScale;

      // Glow
      canvas.drawCircle(Offset(x, y), 16, Paint()
        ..shader = RadialGradient(
          colors: [obj.color.withOpacity(0.4 * fade), obj.color.withOpacity(0.0)],
        ).createShader(const Offset(0, 0) & Size(32, 32)));

      // Dot
      canvas.drawCircle(Offset(x, y), 8, Paint()..color = obj.color.withOpacity(fade));
      canvas.drawCircle(Offset(x, y), 8, Paint()
        ..color = Colors.white.withOpacity(0.5 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);

      // Label
      if (t < 0.5) {
        final off = (y < centerY) ? const Offset(16, -12) : const Offset(16, 12);
        _drawText(canvas, obj.object.name, x + off.dx, y + off.dy,
            fontSize: 14, fontWeight: FontWeight.bold, color: obj.color.withOpacity(fade));
        _drawText(canvas, formatDistance(obj.distance), x + off.dx, y + off.dy + 18,
            fontSize: 12, color: Colors.white.withOpacity(0.85 * fade));
      } else {
        _drawText(canvas, obj.object.name, x, y - 18,
            fontSize: 13, fontWeight: FontWeight.bold, color: obj.color.withOpacity(fade));
        _drawText(canvas, formatDistance(obj.distance), x, y + 2,
            fontSize: 11, color: Colors.white.withOpacity(0.85 * fade));
      }
    }
  }

  void _drawARMarkers(Canvas canvas, Size size, double opacity) {
    final halfFov = fov / 2;
    final centerY = size.height * 0.38;

    for (final obj in rawObjects) {
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

      final x = size.width / 2 + (angleDiff / halfFov) * (size.width / 2);

      _drawARMarker(canvas, obj, x, centerY, distance, angleDiff, color, icon, opacity);
    }
  }

  void _drawARMarker(Canvas canvas, SavedObject obj, double x, double centerY,
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
    final glowRadius = scaledIconSize * 1.0;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.6 * markerOpacity), color.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: Offset(x, centerY), radius: glowRadius));
    canvas.drawCircle(Offset(x, centerY), glowRadius, glowPaint);

    // Pill
    final pillW = scaledIconSize + 20;
    final pillH = scaledIconSize + 14;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, centerY), width: pillW, height: pillH),
      const Radius.circular(20),
    );

    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.95 * markerOpacity),
          color.withOpacity(0.75 * markerOpacity),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(pillRect.outerRect);
    canvas.drawRRect(pillRect, bgPaint);

    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = Colors.white.withOpacity(0.6 * markerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      Offset(x, centerY),
      scaledIconSize / 2,
      Paint()..color = Colors.white.withOpacity(0.3 * markerOpacity),
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

    // Label card
    final labelY = centerY + pillH / 2 + 6;
    final labelW = pillW + 20;
    const labelH = 40.0;

    final labelBgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, labelY + 18), width: labelW, height: labelH),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      labelBgRect,
      Paint()..color = Colors.black.withOpacity(0.8 * markerOpacity),
    );
    canvas.drawRRect(
      labelBgRect,
      Paint()
        ..color = Colors.white.withOpacity(0.2 * markerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    _drawText(canvas, obj.name, x, labelY + 4,
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.white.withOpacity(0.95 * markerOpacity));
    _drawText(canvas, _formatDistance(distance), x, labelY + 22,
        fontSize: 12,
        color: color.withOpacity(0.95 * markerOpacity));
  }

  void _drawEdgeDot(Canvas canvas, double angleDiff, Color color, double distance, double opacity) {
    final x = angleDiff < 0 ? 20.0 : screenSize.width - 20.0;
    final centerY = screenSize.height * 0.38;

    canvas.drawCircle(Offset(x, centerY), 10, Paint()..color = color.withOpacity(0.95 * opacity));
    canvas.drawCircle(Offset(x, centerY), 10, Paint()
      ..color = Colors.white.withOpacity(0.6 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    final arrowIcon = angleDiff < 0 ? Icons.chevron_left : Icons.chevron_right;
    final arrowPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(arrowIcon.codePoint),
        style: TextStyle(
          fontSize: 22, color: color.withOpacity(0.95 * opacity),
          fontFamily: arrowIcon.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    arrowPainter.layout();
    arrowPainter.paint(canvas, Offset(x - arrowPainter.width / 2, centerY - arrowPainter.height / 2 - 16));

    _drawText(canvas, _formatDistance(distance), x, centerY + 22,
        fontSize: 13, color: Colors.white.withOpacity(0.9 * opacity));
  }

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, FontWeight fontWeight = FontWeight.normal, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color, fontSize: fontSize, fontWeight: fontWeight,
          shadows: const [
            Shadow(blurRadius: 10, color: Color(0xEE000000)),
            Shadow(blurRadius: 3, color: Color(0xCC000000)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  bool _isPointInsidePolygon(Offset point, List<Offset> polygon) {
    int intersections = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy)) {
        final xInt = polygon[j].dx + (point.dy - polygon[j].dy) /
            (polygon[i].dy - polygon[j].dy) * (polygon[i].dx - polygon[j].dx);
        if (point.dx < xInt) intersections++;
      }
    }
    return intersections % 2 == 1;
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
    return (_toDegrees(math.atan2(y, x)) + 360) % 360;
  }

  double _normalizeAngle(double angle) {
    while (angle > 180) angle -= 360;
    while (angle < -180) angle += 360;
    return angle;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
  double _toDegrees(double radians) => radians * 180 / math.pi;

  double _iconSizeForDistance(double distance) {
    if (distance < 10) return 60;
    if (distance < 100) return 52;
    if (distance < 500) return 44;
    return 38;
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  bool shouldRepaint(UnifiedARPainter oldDelegate) {
    return (oldDelegate.heading - heading).abs() > 0.5 ||
        oldDelegate.objects != objects ||
        oldDelegate.groups != groups ||
        (oldDelegate.tilt - tilt).abs() > 0.01 ||
        oldDelegate.currentPosition != currentPosition;
  }
}
