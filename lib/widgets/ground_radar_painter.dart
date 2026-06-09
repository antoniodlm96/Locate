import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
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
    final radius = math.min(size.width, size.height) * 0.42 * (0.6 + 0.4 * (1 - t));

    final bgOpacity = (1 - t).clamp(0.0, 1.0);

    if (bgOpacity > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0B0E1A).withOpacity(0.95 * bgOpacity),
              const Color(0xFF0B0E1A).withOpacity(0.85 * bgOpacity),
              Colors.transparent,
            ],
            stops: [0.0, 0.6 * (1 - t), 1.0],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    final ringOpacity = (1 - t).clamp(0.0, 1.0);
    if (ringOpacity > 0.01 && yScale > 0.01) {
      final nSteps = 32;
      for (int ring = 1; ring <= 4; ring++) {
        final r = radius * ring / 4;
        final path = Path();
        for (int i = 0; i <= nSteps; i++) {
          final angle = 2 * math.pi * i / nSteps;
          final px = centerX + r * math.sin(angle);
          final py = centerY - r * math.cos(angle) * yScale;
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(0.05 * ringOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      // Grid lines
      for (int i = 0; i < 6; i++) {
        final angle = i * math.pi / 6;
        canvas.drawLine(
          Offset(centerX, centerY),
          Offset(centerX + radius * math.sin(angle), centerY - radius * math.cos(angle) * yScale),
          Paint()
            ..color = Colors.white.withOpacity(0.02 * ringOpacity)
            ..strokeWidth = 0.5,
        );
      }

      // Cardinal points
      final cardinals = <String, double>{
        'N': -heading, 'E': 90 - heading, 'S': 180 - heading, 'O': 270 - heading,
      };
      for (final entry in cardinals.entries) {
        final angleRad = entry.value * math.pi / 180;
        final lx = centerX + (radius + 20) * math.sin(angleRad);
        final ly = centerY - (radius + 20) * math.cos(angleRad) * yScale;
        final isNorth = entry.key == 'N';
        _drawText(canvas, entry.key, lx, ly,
          fontSize: isNorth ? (18 * ringOpacity).clamp(8.0, 18.0) : (14 * ringOpacity).clamp(6.0, 14.0),
          fontWeight: isNorth ? FontWeight.bold : FontWeight.w500,
          color: Colors.white.withOpacity((isNorth ? 0.9 : 0.45) * ringOpacity),
        );
      }

      // Direction arrow
      if (ringOpacity > 0.1) {
        final arrowPaint = Paint()
          ..color = Colors.white.withOpacity(0.5 * ringOpacity);
        final arrowPath = Path()
          ..moveTo(centerX, centerY - radius * yScale - 12 * ringOpacity)
          ..lineTo(centerX - 7 * ringOpacity, centerY - radius * yScale + 2)
          ..lineTo(centerX + 7 * ringOpacity, centerY - radius * yScale + 2)
          ..close();
        canvas.drawPath(arrowPath, arrowPaint);
        canvas.drawCircle(Offset(centerX, centerY), 2, Paint()..color = Colors.white.withOpacity(0.4 * ringOpacity));
      }
    }

    if (objects.isEmpty) {
      if (t < 0.5) {
        _drawText(canvas, 'Sin objetos cerca', centerX, centerY + 35 * (1 - t),
            fontSize: 15 * (1 - t * 0.5), color: Colors.white.withOpacity(0.3 * (1 - t)));
      }
      return;
    }

    final maxDist = objects.cast<ObjectWithDistance>().map((o) => o.distance).reduce(math.max);
    final radarMax = math.max(50.0, math.min(maxDist * 1.3, 500.0));

    final Map<int, Offset> objectGroundPositions = {};

    for (final obj in objects) {
      final angleDiff = obj.bearing - heading;
      final angleRad = angleDiff * math.pi / 180;

      // Polar radar position (t=0)
      final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
      final objR = distFactor * radius * 0.88;
      final polarX = centerX + objR * math.sin(angleRad);
      final polarY = centerY - objR * math.cos(angleRad) * yScale;

      // Ground perspective position (t=1)
      final groundX = centerX + (angleDiff / 90) * (centerX * 0.85);
      final groundY = centerY;

      final fadeIn = (t - 0.5).clamp(0.0, 1.0);

      if (t < 0.85) {
        final ox = _lerp(polarX, groundX, t * 0.7);
        final oy = polarY;

        objectGroundPositions[obj.object.id!] = Offset(ox, oy);

        // Glow
        canvas.drawCircle(
          Offset(ox, oy), 10 * (1 - t * 0.5),
          Paint()
            ..shader = RadialGradient(
              colors: [obj.color.withOpacity(0.25 * (1 - t)), obj.color.withOpacity(0.0)],
            ).createShader(Rect.fromCircle(center: Offset(ox, oy), radius: 10)),
        );

        // Dot
        final dotSize = (6 * (1 - t * 0.4)).clamp(3.5, 6.0);
        canvas.drawCircle(Offset(ox, oy), dotSize, Paint()..color = obj.color);
        canvas.drawCircle(Offset(ox, oy), dotSize, Paint()
          ..color = Colors.white.withOpacity(0.3 * (1 - t * 0.5))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

        // Labels in radar mode
        final labelOffset = (objR < radius * 0.3) ? const Offset(14, -12) : const Offset(12, -10);
        _drawText(canvas, obj.object.name, ox + labelOffset.dx, oy + labelOffset.dy,
            fontSize: 12, fontWeight: FontWeight.w600, color: obj.color);
        _drawText(canvas, formatDistance(obj.distance), ox + labelOffset.dx, oy + labelOffset.dy + 15,
            fontSize: 10, color: Colors.white60);
      } else {
        // At high tilt, draw on ground with perspective
        objectGroundPositions[obj.object.id!] = Offset(groundX, groundY);

        final dotSize = _lerp(4.0, 7.0, fadeIn);
        canvas.drawCircle(Offset(groundX, groundY), dotSize, Paint()..color = obj.color);
        canvas.drawCircle(Offset(groundX, groundY), dotSize, Paint()
          ..color = Colors.white.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

        _drawText(canvas, obj.object.name, groundX, groundY - 16,
            fontSize: 10, fontWeight: FontWeight.w600, color: obj.color.withOpacity(0.9));
        _drawText(canvas, formatDistance(obj.distance), groundX, groundY - 4,
            fontSize: 9, color: Colors.white70);
      }
    }

    // Draw groups
    for (final group in groups) {
      final members = group.sortedObjects;
      if (members.length < 2) continue;

      final positions = <Offset>[];
      for (final m in members) {
        final id = m.id;
        if (id == null) continue;
        if (objectGroundPositions.containsKey(id)) {
          positions.add(objectGroundPositions[id]!);
        }
      }
      if (positions.length < 2) continue;

      final baseColor = group.type == 'area' ? Colors.green : Colors.cyan;
      final groupOpacity = (0.3 + 0.5 * t).clamp(0.0, 1.0);

      if (group.type == 'area' && positions.length >= 3) {
        final fillPaint = Paint()
          ..color = baseColor.withOpacity(0.1 * groupOpacity);
        final path = Path()..moveTo(positions[0].dx, positions[0].dy);
        for (int i = 1; i < positions.length; i++) {
          path.lineTo(positions[i].dx, positions[i].dy);
        }
        path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, Paint()
          ..color = baseColor.withOpacity(0.5 * groupOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

        if (t > 0.3) {
          final cx = centerX;
          if (_isPointInsidePolygon(Offset(cx, centerY), positions)) {
            _drawText(canvas, '● DENTRO DEL ÁREA', cx, centerY - 30,
                fontSize: 11, fontWeight: FontWeight.bold, color: baseColor.withOpacity(0.9 * groupOpacity));
          }
        }
      } else {
        for (int i = 0; i < positions.length - 1; i++) {
          canvas.drawLine(positions[i], positions[i + 1], Paint()
            ..color = baseColor.withOpacity(0.5 * groupOpacity)
            ..strokeWidth = 3);

          if (t < 0.8) {
            final mid = Offset(
              (positions[i].dx + positions[i + 1].dx) / 2,
              (positions[i].dy + positions[i + 1].dy) / 2,
            );
            final segDist = Geolocator.distanceBetween(
              group.sortedObjects[i].latitude, group.sortedObjects[i].longitude,
              group.sortedObjects[i + 1].latitude, group.sortedObjects[i + 1].longitude,
            );
            _drawText(canvas, formatDistance(segDist), mid.dx, mid.dy - 8,
                fontSize: 9, color: Colors.white.withOpacity(0.5 * groupOpacity));
          }
        }
      }

      double cx = 0, cy = 0;
      for (final p in positions) { cx += p.dx; cy += p.dy; }
      cx /= positions.length;
      cy /= positions.length;
      _drawText(canvas, group.name, cx, cy,
          fontSize: 10, fontWeight: FontWeight.bold,
          color: baseColor.withOpacity(0.8 * groupOpacity));
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  bool _isPointInsidePolygon(Offset point, List<Offset> polygon) {
    int intersections = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy)) {
        final xIntersect = polygon[j].dx +
            (point.dy - polygon[j].dy) / (polygon[i].dy - polygon[j].dy) *
                (polygon[i].dx - polygon[j].dx);
        if (point.dx < xIntersect) intersections++;
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
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
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
