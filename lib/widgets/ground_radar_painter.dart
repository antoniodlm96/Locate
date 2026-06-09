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

    // Background: opaque until near-vertical, then fades
    final bgFade = ((t - 0.75) / 0.17).clamp(0.0, 1.0);
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

    // === Rings (bold, compressed by yScale) ===
    final nSteps = 64;
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
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - ring * 0.3);
    }

    // Grid lines (bolder)
    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 6;
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX + radius * math.sin(angle), centerY - radius * math.cos(angle) * yScale),
        Paint()..color = Colors.white.withOpacity(0.12)..strokeWidth = 1.0,
      );
    }

    // === Cardinal points (bold) ===
    final cardinals = <String, double>{
      'N': -heading, 'E': 90 - heading, 'S': 180 - heading, 'O': 270 - heading,
    };
    for (final entry in cardinals.entries) {
      final angleRad = entry.value * math.pi / 180;
      final lx = centerX + (radius + 24) * math.sin(angleRad);
      final ly = centerY - (radius + 24) * math.cos(angleRad) * yScale;
      final isNorth = entry.key == 'N';
      _drawText(canvas, entry.key, lx, ly,
        fontSize: isNorth ? 24 : 18,
        fontWeight: FontWeight.bold,
        color: Colors.white.withOpacity(isNorth ? 1.0 : 0.85),
      );
    }

    // Large direction arrow
    final arrowP = Offset(centerX, centerY - radius * yScale - 18);
    canvas.drawPath(
      Path()
        ..moveTo(arrowP.dx, arrowP.dy)
        ..lineTo(arrowP.dx - 10, arrowP.dy + 20)
        ..lineTo(arrowP.dx + 10, arrowP.dy + 20)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.85),
    );
    canvas.drawCircle(Offset(centerX, centerY), 3.5, Paint()..color = Colors.white.withOpacity(0.85));

    if (objects.isEmpty) {
      _drawText(canvas, 'Sin objetos cerca', centerX, centerY + 35,
          fontSize: 17, color: Colors.white.withOpacity(0.5));
      return;
    }

    final maxDist = objects.map((o) => o.distance).reduce(math.max);
    final radarMax = math.max(50.0, math.min(maxDist * 1.3, 500.0));
    final radialExtent = radius * 0.88;

    // === Groups: always polar coordinates (no coordinate blend) ===
    // Group positions computed from pure polar formula so shape stays stable
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

    // Render groups first (behind objects)
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

    // === Objects: polar→linear transition between tilt 0.5 and 0.85 ===
    final visibleCone = 180.0 + (1.0 - t) * 180.0;
    final polarBlend = ((t - 0.5) / 0.35).clamp(0.0, 1.0);

    for (final obj in objects) {
      final bearingDiff = obj.bearing - heading;
      final absDiff = bearingDiff.abs();
      final angleRad = bearingDiff * math.pi / 180;

      final excess = (absDiff - visibleCone * 0.5) / (visibleCone * 0.5);
      final fade = (1.0 - excess * 2).clamp(0.0, 1.0);
      if (fade < 0.01) continue;

      final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
      final objR = distFactor * radialExtent;

      final polarX = centerX + objR * math.sin(angleRad);
      final polarY = centerY - objR * math.cos(angleRad) * yScale;

      final linearX = centerX + (bearingDiff / 90.0) * radialExtent * distFactor;
      final linearY = centerY - radialExtent * (0.2 + distFactor * 0.6) * (1.0 - yScale);

      final x = _lerp(polarX, linearX, polarBlend);
      final y = _lerp(polarY, linearY, polarBlend);

      // Glow
      canvas.drawCircle(Offset(x, y), 16, Paint()
        ..shader = RadialGradient(
          colors: [obj.color.withOpacity(0.4 * fade), obj.color.withOpacity(0.0)],
        ).createShader(const Offset(0, 0) & const Size(32, 32)));

      // Dot
      canvas.drawCircle(Offset(x, y), 8, Paint()..color = obj.color.withOpacity(fade));
      canvas.drawCircle(Offset(x, y), 8, Paint()
        ..color = Colors.white.withOpacity(0.5 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);

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

  @override
  bool shouldRepaint(GroundRadarPainter oldDelegate) {
    return (oldDelegate.heading - heading).abs() > 0.5 ||
        oldDelegate.objects != objects ||
        oldDelegate.groups != groups ||
        (oldDelegate.tilt - tilt).abs() > 0.01;
  }
}
