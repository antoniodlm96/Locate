import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/object_group.dart';
import '../screens/ar_view_screen.dart';

class GroundRadarPainter extends CustomPainter {
  final List<ObjectWithDistance> objects;
  final List<ObjectGroup> groups;
  final double heading;
  final double tilt;

  GroundRadarPainter({
    required this.objects,
    required this.groups,
    required this.heading,
    required this.tilt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = tilt.clamp(0.0, 1.0);
    final yScale = math.cos(t * math.pi / 2);
    final centerX = size.width / 2;
    final centerY = _lerp(size.height * 0.45, size.height * 0.82, t);
    final radius = math.min(size.width, size.height) * 0.42;

    // Background fades as phone tilts
    final bgFade = ((t - 0.15) / 0.5).clamp(0.0, 1.0);
    final bgOpacity = 1.0 - bgFade;
    if (bgOpacity > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0B0E1A).withOpacity((0.98 * bgOpacity).clamp(0.0, 1.0)),
            const Color(0xFF0B0E1A).withOpacity((0.90 * bgOpacity).clamp(0.0, 1.0)),
            const Color(0xFF0B0E1A).withOpacity((0.6 * bgOpacity).clamp(0.0, 1.0)),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // === Rings (always opaque, compressed by yScale) ===
    final nSteps = 48;
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
      final alpha = (5 - ring) * 0.03;
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 - ring * 0.2);
    }

    // Grid lines
    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 6;
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX + radius * math.sin(angle), centerY - radius * math.cos(angle) * yScale),
        Paint()..color = Colors.white.withOpacity(0.04)..strokeWidth = 0.5,
      );
    }

    // === Cardinal points ===
    final cardinals = <String, double>{
      'N': -heading, 'E': 90 - heading, 'S': 180 - heading, 'O': 270 - heading,
    };
    for (final entry in cardinals.entries) {
      final angleRad = entry.value * math.pi / 180;
      final lx = centerX + (radius + 20) * math.sin(angleRad);
      final ly = centerY - (radius + 20) * math.cos(angleRad) * yScale;
      final isNorth = entry.key == 'N';
      _drawText(canvas, entry.key, lx, ly,
        fontSize: isNorth ? 19 : 15,
        fontWeight: isNorth ? FontWeight.bold : FontWeight.w500,
        color: Colors.white.withOpacity(isNorth ? 0.95 : 0.6),
      );
    }

    // Direction arrow
    final arrowP = Offset(centerX, centerY - radius * yScale - 14);
    canvas.drawPath(
      Path()
        ..moveTo(arrowP.dx, arrowP.dy)
        ..lineTo(arrowP.dx - 7, arrowP.dy + 16)
        ..lineTo(arrowP.dx + 7, arrowP.dy + 16)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.6),
    );
    canvas.drawCircle(Offset(centerX, centerY), 2.5, Paint()..color = Colors.white.withOpacity(0.6));

    if (objects.isEmpty) {
      _drawText(canvas, 'Sin objetos cerca', centerX, centerY + 35,
          fontSize: 15, color: Colors.white.withOpacity(0.35));
      return;
    }

    final maxDist = objects.map((o) => o.distance).reduce(math.max);
    final radarMax = math.max(50.0, math.min(maxDist * 1.3, 500.0));

    // === Objects: transición suave polar→lineal entre tilt 0.4 y 0.8 ===
    final Map<int, Offset> objectPositions = {};

    // Visibility cone narrows from 360° to 180° as tilt increases
    final visibleCone = 180.0 + (1.0 - t) * 180.0;

    // Blend: 0 = polar (radar), 1 = lineal (ground projection)
    final polarBlend = ((t - 0.4) / 0.4).clamp(0.0, 1.0);
    final radialExtent = radius * 0.88;

    for (final obj in objects) {
      final bearingDiff = obj.bearing - heading;
      final absDiff = bearingDiff.abs();
      final angleRad = bearingDiff * math.pi / 180;

      final excess = (absDiff - visibleCone * 0.5) / (visibleCone * 0.5);
      final fade = (1.0 - excess * 2).clamp(0.0, 1.0);
      if (fade < 0.01) continue;

      final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
      final objR = distFactor * radialExtent;

      // Polar: circular radar position
      final polarX = centerX + objR * math.sin(angleRad);
      final polarY = centerY - objR * math.cos(angleRad) * yScale;

      // Linear: bearing maps to X, distance maps to Y (near=bottom, far=top)
      final linearX = centerX + (bearingDiff / 90.0) * radialExtent * distFactor;
      final linearY = centerY - radialExtent * (0.2 + distFactor * 0.6) * (1.0 - yScale);

      final x = _lerp(polarX, linearX, polarBlend);
      final y = _lerp(polarY, linearY, polarBlend);

      objectPositions[obj.object.id!] = Offset(x, y);

      // Dot
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = obj.color.withOpacity(fade));
      canvas.drawCircle(Offset(x, y), 6, Paint()
        ..color = Colors.white.withOpacity(0.35 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      // Label
      if (t < 0.6) {
        final off = (y < centerY) ? const Offset(12, -10) : const Offset(12, 10);
        _drawText(canvas, obj.object.name, x + off.dx, y + off.dy,
            fontSize: 12, fontWeight: FontWeight.w600, color: obj.color.withOpacity(0.95 * fade));
        _drawText(canvas, formatDistance(obj.distance), x + off.dx, y + off.dy + 15,
            fontSize: 10, color: Colors.white.withOpacity(0.7 * fade));
      } else {
        _drawText(canvas, obj.object.name, x, y - 14,
            fontSize: 10, fontWeight: FontWeight.w600, color: obj.color.withOpacity(0.95 * fade));
        _drawText(canvas, formatDistance(obj.distance), x, y,
            fontSize: 9, color: Colors.white.withOpacity(0.7 * fade));
      }
    }

    // === Groups ===
    for (final group in groups) {
      final members = group.sortedObjects;
      if (members.length < 2) continue;

      final pts = <Offset>[];
      for (final m in members) {
        final id = m.id;
        if (id == null) continue;
        final pos = objectPositions[id];
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
            colors: [baseColor.withOpacity(0.12), baseColor.withOpacity(0.02)],
          ).createShader(Rect.fromPoints(pts[0], pts[pts.length ~/ 2]).inflate(50)));
        canvas.drawPath(path, Paint()
          ..color = baseColor.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);

        if (t > 0.3 && _isPointInsidePolygon(Offset(centerX, centerY), pts)) {
          _drawText(canvas, '● DENTRO DEL ÁREA', centerX, centerY - 28,
              fontSize: 11, fontWeight: FontWeight.bold, color: baseColor.withOpacity(0.9));
        }
      } else {
        for (int i = 0; i < pts.length - 1; i++) {
          canvas.drawLine(pts[i], pts[i + 1], Paint()
            ..color = baseColor.withOpacity(0.55)
            ..strokeWidth = 3);

          if (t < 0.7) {
            final mid = (pts[i] + pts[i + 1]) / 2;
            final segDist = Geolocator.distanceBetween(
              group.sortedObjects[i].latitude, group.sortedObjects[i].longitude,
              group.sortedObjects[i + 1].latitude, group.sortedObjects[i + 1].longitude,
            );
            _drawText(canvas, formatDistance(segDist), mid.dx, mid.dy - 8,
                fontSize: 9, color: Colors.white.withOpacity(0.5));
          }
        }
      }

      double cx = 0, cy = 0;
      for (final p in pts) { cx += p.dx; cy += p.dy; }
      _drawText(canvas, group.name, cx / pts.length, cy / pts.length,
          fontSize: 10, fontWeight: FontWeight.bold, color: baseColor.withOpacity(0.85));
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

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

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, FontWeight fontWeight = FontWeight.normal, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color, fontSize: fontSize, fontWeight: fontWeight,
          shadows: const [Shadow(blurRadius: 8, color: Color(0xCC000000))],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  @override
  bool shouldRepaint(GroundRadarPainter oldDelegate) {
    return (oldDelegate.heading - heading).abs() > 0.5 ||
        oldDelegate.objects != objects ||
        oldDelegate.groups != groups ||
        (oldDelegate.tilt - tilt).abs() > 0.01;
  }
}
