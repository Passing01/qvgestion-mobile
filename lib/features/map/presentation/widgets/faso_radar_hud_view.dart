import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:qvgestion_mobile/features/guidance/data/models/radar_scene_model.dart';
import 'package:qvgestion_mobile/features/places/data/models/place_model.dart';
import 'package:qvgestion_mobile/features/reports/data/models/report_model.dart';
import 'package:qvgestion_mobile/features/routes/data/models/route_model.dart';

/// Vue immersive "Radar Live / Cockpit Voiture Autonome" pour FASO NAV.
/// Reconstruit en 3D temps réel à 60 FPS la chaussée devant le conducteur,
/// la trajectoire lumineuse, les ondes radar, les échangeurs/feux/monuments,
/// les repères locaux proches et le trafic environnant sans recourir à la caméra vidéo.
class FasoRadarHudView extends StatefulWidget {
  final LatLng vehiclePosition;
  final double vehicleHeadingDeg;
  final double speedKmh;
  final String transportMode;
  final RouteModel? route;
  final RadarSceneModel? radarScene;
  final List<ReportModel> activeReports;
  final List<PlaceModel> nearbyPlaces;
  final VoidCallback onSwitchToMap;

  const FasoRadarHudView({
    super.key,
    required this.vehiclePosition,
    required this.vehicleHeadingDeg,
    required this.speedKmh,
    required this.transportMode,
    this.route,
    this.radarScene,
    this.activeReports = const [],
    this.nearbyPlaces = const [],
    required this.onSwitchToMap,
  });

  @override
  State<FasoRadarHudView> createState() => _FasoRadarHudViewState();
}

class _FasoRadarHudViewState extends State<FasoRadarHudView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  static bool get _isUnderTest {
    final binding = WidgetsBinding.instance.runtimeType.toString();
    return binding.contains('Test') ||
        const bool.fromEnvironment('FLUTTER_TEST_RUNNER');
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (!_isUnderTest) {
      _pulseController.repeat();
    } else {
      _pulseController.value = 0.45;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<_RadarNearbyPoi> _collectVisiblePlaces() {
    final scene = widget.radarScene;
    final seenNames = <String>{
      if (scene != null) ...scene.landmarks.map((l) => l.name.trim().toLowerCase()),
      if (scene != null) ...scene.monuments3d.map((m) => m.name.trim().toLowerCase()),
    };
    final out = <_RadarNearbyPoi>[];
    const distCalc = Distance();

    if (scene != null) {
      for (final lm in scene.landmarks) {
        if (lm.distanceM <= 360.0) {
          out.add(_RadarNearbyPoi(
            name: lm.name,
            latitude: lm.latitude,
            longitude: lm.longitude,
            distanceM: lm.distanceM,
            isOfficialLandmark: true,
          ));
        }
      }
    }

    for (final p in widget.nearbyPlaces) {
      final key = p.nom.trim().toLowerCase();
      if (key.isEmpty || seenNames.contains(key)) continue;
      final d = distCalc.as(
        LengthUnit.Meter,
        widget.vehiclePosition,
        LatLng(p.latitude, p.longitude),
      );
      if (d <= 360.0) {
        seenNames.add(key);
        out.add(_RadarNearbyPoi(
          name: p.nom,
          latitude: p.latitude,
          longitude: p.longitude,
          distanceM: d,
          isOfficialLandmark: false,
        ));
      }
    }

    out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return out.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.radarScene;
    final visiblePois = _collectVisiblePlaces();
    final detectedCount = (scene?.roadFeatures.length ?? 0) +
        (scene?.monuments3d.length ?? 0) +
        (scene?.trafficSegments.length ?? 0) +
        visiblePois.length +
        widget.activeReports.length;

    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900.0;
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      key: const Key('faso_radar_hud_view'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.24, 0.65, 1.0],
          colors: [
            Color(0xFF030712),
            Color(0xFF0A1628),
            Color(0xFF0B192E),
            Color(0xFF040914),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _FasoRadarPainter(
                      phase: _pulseController.value,
                      vehiclePosition: widget.vehiclePosition,
                      headingDeg: widget.vehicleHeadingDeg,
                      speedKmh: widget.speedKmh,
                      transportMode: widget.transportMode,
                      route: widget.route,
                      radarScene: widget.radarScene,
                      activeReports: widget.activeReports,
                      visiblePois: visiblePois,
                      centerShiftX: isDesktop ? 130.0 : 0.0,
                    ),
                  );
                },
              ),
            ),
          ),

          // Bandeau télémétrie & bascule rapide vers Carte 3D
          Positioned(
            top: isDesktop ? 18 : topInset + 96,
            left: isDesktop ? 500 : 16,
            right: isDesktop ? 164 : 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.radar_rounded,
                          color: Color(0xFF38BDF8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'RADAR LIVE • $detectedCount obj.',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  key: const Key('btn_exit_radar_view'),
                  onTap: widget.onSwitchToMap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.map_rounded,
                          color: Color(0xFF1E293B),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Carte 3D',
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Badge vitesse instantanée façon cockpit (sans chevauchement avec ActiveNavigationCard)
          Positioned(
            left: isDesktop ? 500 : 16,
            bottom: isDesktop ? 28 : 256,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.speedKmh.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  const Text(
                    'km/h',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _RadarNearbyPoi {
  final String name;
  final double latitude;
  final double longitude;
  final double distanceM;
  final bool isOfficialLandmark;

  const _RadarNearbyPoi({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceM,
    required this.isOfficialLandmark,
  });
}

class _ProjectedPoint {
  final Offset offset;
  final double scale;
  final double depthM;

  const _ProjectedPoint(this.offset, this.scale, this.depthM);
}

class _FasoRadarPainter extends CustomPainter {
  final double phase;
  final LatLng vehiclePosition;
  final double headingDeg;
  final double speedKmh;
  final String transportMode;
  final RouteModel? route;
  final RadarSceneModel? radarScene;
  final List<ReportModel> activeReports;
  final List<_RadarNearbyPoi> visiblePois;
  final double centerShiftX;

  _FasoRadarPainter({
    required this.phase,
    required this.vehiclePosition,
    required this.headingDeg,
    required this.speedKmh,
    required this.transportMode,
    required this.route,
    required this.radarScene,
    required this.activeReports,
    required this.visiblePois,
    this.centerShiftX = 0.0,
  });

  static const double _maxRangeM = 360.0;
  static const double _cameraHeightM = 11.0;
  static const double _nearOffsetM = 14.0;

  double _centerX(Size size) => (size.width * 0.5 + centerShiftX).clamp(
        size.width * 0.35,
        size.width * 0.72,
      );

  /// Transforme une coordonnée WGS84 en coordonnées locales (x droite, z avant) en mètres
  Offset _toLocalMeters(double lat, double lon) {
    final dNorth = (lat - vehiclePosition.latitude) * 111320.0;
    final dEast = (lon - vehiclePosition.longitude) *
        111320.0 *
        math.cos(vehiclePosition.latitude * math.pi / 180.0);
    final rad = headingDeg * math.pi / 180.0;
    final forward = dNorth * math.cos(rad) + dEast * math.sin(rad);
    final right = -dNorth * math.sin(rad) + dEast * math.cos(rad);
    return Offset(right, forward);
  }

  /// Projection perspective 3D (x latéral en m, z avant en m) -> écran bornée sur Desktop
  _ProjectedPoint? _project(Size size, double xM, double zM) {
    if (zM < -8.0 || zM > _maxRangeM) return null;
    final horizonY = size.height * 0.24;
    final egoY = size.height * 0.76;
    final zEff = math.max(1.0, zM + _nearOffsetM);
    final scale = _cameraHeightM / zEff;
    final normDepth = (zM + 8.0) / (_maxRangeM + 8.0);
    final screenY = egoY - (egoY - horizonY) * math.pow(normDepth, 0.56);
    final refWidth = math.min(size.width, 580.0);
    final screenX = _centerX(size) + xM * scale * (refWidth * 0.115);
    return _ProjectedPoint(Offset(screenX, screenY), scale.clamp(0.08, 1.35), zM);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final egoBase = _project(size, 0, 0)?.offset ??
        Offset(_centerX(size), size.height * 0.76);
    final horizonY = size.height * 0.24;

    // 1. Halo atmosphérique d'horizon façon cockpit Tesla FSD
    final skyGlow = Paint()
      ..shader = RadialGradient(
        center: Alignment((_centerX(size) / size.width) * 2 - 1, -0.52),
        radius: 0.9,
        colors: [
          const Color(0xFF0EA5E9).withValues(alpha: 0.20),
          const Color(0xFF1D4ED8).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), skyGlow);

    // 2. Grille LiDAR perspective calibrée
    _drawPerspectiveGrid(canvas, size, egoBase, horizonY);

    // 3. Ondes radar pulsées depuis le véhicule
    _drawRadarWaves(canvas, size, egoBase);

    // 4. Chaussée & ruban lumineux séquentiel devant le véhicule
    _drawProjectedRoadAndCorridor(canvas, size);

    // 5. Objets 3D détectés : Monuments, Lieux proches, Feux, Signalements, Trafic
    _drawDetectedSceneObjects(canvas, size);

    // 6. Véhicule Ego unique au premier plan
    _drawEgoVehicle(canvas, egoBase);
  }

  void _drawPerspectiveGrid(
      Canvas canvas, Size size, Offset egoBase, double horizonY) {
    final gridPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    // Lignes longitudinales fuyant vers le point de fuite
    for (var i = -5; i <= 5; i++) {
      final pNear = _project(size, i * 9.0, 0);
      final pFar = _project(size, i * 9.0, _maxRangeM);
      if (pNear != null && pFar != null) {
        canvas.drawLine(pNear.offset, pFar.offset, gridPaint);
      }
    }

    // Repères de distance (50m, 100m, 200m, 300m)
    for (final dist in const [50.0, 100.0, 200.0, 300.0]) {
      final pLeft = _project(size, -45.0, dist);
      final pRight = _project(size, 45.0, dist);
      if (pLeft != null && pRight != null) {
        canvas.drawLine(pLeft.offset, pRight.offset, gridPaint);
        final tp = TextPainter(
          text: TextSpan(
            text: '${dist.round()} m',
            style: TextStyle(
              color: const Color(0xFF7DD3FC).withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pRight.offset.dx + 6, pRight.offset.dy - 7));
      }
    }

    // Ligne d'horizon néon
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.30)
        ..strokeWidth = 1.4,
    );
  }

  void _drawRadarWaves(Canvas canvas, Size size, Offset egoBase) {
    final waveMaxRadius = math.min(size.width, 580.0) * 0.58;
    for (var i = 0; i < 3; i++) {
      final t = (phase + i / 3.0) % 1.0;
      final radius = 38.0 + t * waveMaxRadius;
      final alpha = (1.0 - t) * 0.45;
      final rect = Rect.fromCenter(
        center: Offset(egoBase.dx, egoBase.dy - 10),
        width: radius * 1.9,
        height: radius * 0.58,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1.0 - t * 0.5)
          ..color = const Color(0xFF38BDF8).withValues(alpha: alpha),
      );
    }
  }

  /// Extrait la portion CONTINUE de l'itinéraire devant le véhicule (sans jamais trier par dy).
  List<Offset> _extractCorridorPointsLocal() {
    final geom = route?.geometry ?? const [];
    if (geom.length < 2) {
      return const [
        Offset(0, 0),
        Offset(0, 60),
        Offset(0, 140),
        Offset(0, 240),
        Offset(0, 340),
      ];
    }

    final allLocal = <Offset>[];
    for (final raw in geom) {
      if (raw.length >= 2) {
        final lat = raw[0] > 5.0 ? raw[0] : raw[1];
        final lon = raw[0] > 5.0 ? raw[1] : raw[0];
        allLocal.add(_toLocalMeters(lat, lon));
      }
    }
    if (allLocal.length < 2) {
      return const [Offset(0, 0), Offset(0, 120), Offset(0, 280)];
    }

    // Trouver le segment le plus proche de (0, 0)
    var bestSeg = 0;
    var bestDist2 = double.infinity;
    var bestT = 0.0;
    for (var i = 0; i < allLocal.length - 1; i++) {
      final a = allLocal[i];
      final b = allLocal[i + 1];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len2 = dx * dx + dy * dy;
      final t = len2 > 1e-6
          ? ((-(a.dx * dx + a.dy * dy)) / len2).clamp(0.0, 1.0)
          : 0.0;
      final px = a.dx + t * dx;
      final py = a.dy + t * dy;
      final d2 = px * px + py * py;
      if (d2 < bestDist2) {
        bestDist2 = d2;
        bestSeg = i;
        bestT = t;
      }
    }

    final seq = <Offset>[];
    final startA = allLocal[bestSeg];
    final startB = allLocal[bestSeg + 1];
    final projectedStart = Offset(
      startA.dx + bestT * (startB.dx - startA.dx),
      startA.dy + bestT * (startB.dy - startA.dy),
    );
    seq.add(Offset(projectedStart.dx.clamp(-25.0, 25.0), math.max(0.0, projectedStart.dy)));

    for (var i = bestSeg + 1; i < allLocal.length; i++) {
      final prev = seq.last;
      final curr = allLocal[i];
      // Si l'itinéraire part vers l'arrière ou dépasse l'horizon, on coupe proprement le segment
      if (curr.dy < -6.0 && prev.dy < 10.0) break;
      if (curr.dy > _maxRangeM) {
        final denom = curr.dy - prev.dy;
        if (denom.abs() > 1e-3) {
          final t = ((_maxRangeM - prev.dy) / denom).clamp(0.0, 1.0);
          seq.add(Offset(prev.dx + t * (curr.dx - prev.dx), _maxRangeM));
        }
        break;
      }
      if (curr.dy >= -4.0) {
        seq.add(curr);
      }
      if (seq.length >= 28) break;
    }

    if (seq.length < 2) {
      return const [
        Offset(0, 0),
        Offset(0, 60),
        Offset(0, 140),
        Offset(0, 240),
        Offset(0, 340),
      ];
    }
    return seq;
  }

  void _drawProjectedRoadAndCorridor(Canvas canvas, Size size) {
    final localPts = _extractCorridorPointsLocal();
    const halfRoadWidthM = 5.4;
    const halfCorridorWidthM = 2.1;

    final leftEdge = <Offset>[];
    final rightEdge = <Offset>[];
    final corrLeft = <Offset>[];
    final corrRight = <Offset>[];
    final centerPts = <Offset>[];

    for (var i = 0; i < localPts.length; i++) {
      final p = localPts[i];
      final prev = i > 0 ? localPts[i - 1] : p;
      final next = i < localPts.length - 1 ? localPts[i + 1] : p;
      var tx = next.dx - prev.dx;
      var ty = next.dy - prev.dy;
      final len = math.sqrt(tx * tx + ty * ty);
      // Normale latérale perpendiculaire à la direction de la route (tx, ty) -> (ty, -tx)
      final nx = len > 1e-4 ? (ty / len) : 1.0;
      final ny = len > 1e-4 ? (-tx / len) : 0.0;

      final pL = _project(size, p.dx - nx * halfRoadWidthM, p.dy - ny * halfRoadWidthM);
      final pR = _project(size, p.dx + nx * halfRoadWidthM, p.dy + ny * halfRoadWidthM);
      final cL = _project(size, p.dx - nx * halfCorridorWidthM, p.dy - ny * halfCorridorWidthM);
      final cR = _project(size, p.dx + nx * halfCorridorWidthM, p.dy + ny * halfCorridorWidthM);
      final cM = _project(size, p.dx, p.dy);

      if (pL != null && pR != null && cL != null && cR != null && cM != null) {
        leftEdge.add(pL.offset);
        rightEdge.add(pR.offset);
        corrLeft.add(cL.offset);
        corrRight.add(cR.offset);
        centerPts.add(cM.offset);
      }
    }

    if (leftEdge.length < 2) return;

    // Polygone de chaussée asphalte sombre
    final roadPath = Path()..moveTo(leftEdge.first.dx, leftEdge.first.dy);
    for (final pt in leftEdge.skip(1)) {
      roadPath.lineTo(pt.dx, pt.dy);
    }
    for (final pt in rightEdge.reversed) {
      roadPath.lineTo(pt.dx, pt.dy);
    }
    roadPath.close();

    canvas.drawPath(
      roadPath,
      Paint()
        ..color = const Color(0xFF1E293B).withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );

    // Bordures lumineuses de la route
    final edgePaint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.72)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final leftPath = Path()..moveTo(leftEdge.first.dx, leftEdge.first.dy);
    for (final pt in leftEdge.skip(1)) {
      leftPath.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(leftPath, edgePaint);

    final rightPath = Path()..moveTo(rightEdge.first.dx, rightEdge.first.dy);
    for (final pt in rightEdge.skip(1)) {
      rightPath.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(rightPath, edgePaint);

    // Couloir lumineux de trajectoire (ruban bleu Autopilot)
    final corridorPath = Path()..moveTo(corrLeft.first.dx, corrLeft.first.dy);
    for (final pt in corrLeft.skip(1)) {
      corridorPath.lineTo(pt.dx, pt.dy);
    }
    for (final pt in corrRight.reversed) {
      corridorPath.lineTo(pt.dx, pt.dy);
    }
    corridorPath.close();

    canvas.drawPath(
      corridorPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFF38BDF8).withValues(alpha: 0.55),
            const Color(0xFF2563EB).withValues(alpha: 0.22),
          ],
        ).createShader(Rect.fromLTWH(0, size.height * 0.24, size.width, size.height * 0.55)),
    );

    // Ligne centrale blanche de la route
    if (centerPts.length >= 2) {
      final centerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final cPath = Path()..moveTo(centerPts.first.dx, centerPts.first.dy);
      for (final pt in centerPts.skip(1)) {
        cPath.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(cPath, centerPaint);
    }

    // Chevrons animés avançant le long du couloir
    final chevronPaint = Paint()
      ..color = const Color(0xFFE0F2FE).withValues(alpha: 0.85)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 6; i++) {
      final z = ((i / 6.0 + phase) % 1.0) * 140.0 + 16.0;
      final c = _project(size, 0, z);
      final l = _project(size, -1.25, z - 4.0);
      final r = _project(size, 1.25, z - 4.0);
      if (c != null && l != null && r != null) {
        final chev = Path()
          ..moveTo(l.offset.dx, l.offset.dy)
          ..lineTo(c.offset.dx, c.offset.dy)
          ..lineTo(r.offset.dx, r.offset.dy);
        canvas.drawPath(chev, chevronPaint);
      }
    }
  }

  void _drawDetectedSceneObjects(Canvas canvas, Size size) {
    final placedLabels = <Rect>[];

    // 1. Repères locaux & POIs réels autour du véhicule (Pharmacies, Stations, etc.)
    for (final poi in visiblePois) {
      final local = _toLocalMeters(poi.latitude, poi.longitude);
      final proj = _project(size, local.dx, local.dy);
      if (proj == null) continue;
      final bHeight = ((poi.isOfficialLandmark ? 24.0 : 16.0) * proj.scale)
          .clamp(12.0, 48.0);
      final bWidth = (14.0 * proj.scale).clamp(8.0, 26.0);
      final rect = Rect.fromLTWH(
        proj.offset.dx - bWidth / 2,
        proj.offset.dy - bHeight,
        bWidth,
        bHeight,
      );
      final color = poi.isOfficialLandmark
          ? const Color(0xFF38BDF8)
          : const Color(0xFF10B981);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.25),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
      _drawLabelNonOverlapping(
        canvas,
        '${poi.name} (${poi.distanceM.round()}m)',
        Offset(proj.offset.dx, rect.top - 10),
        poi.isOfficialLandmark ? const Color(0xFFBAE6FD) : const Color(0xFFA7F3D0),
        placedLabels,
      );
    }

    final scene = radarScene;
    if (scene != null) {
      // 2. Monuments 3D à l'horizon
      for (final m in scene.monuments3d) {
        final local = _toLocalMeters(m.latitude, m.longitude);
        final proj = _project(size, local.dx, local.dy.clamp(10.0, _maxRangeM));
        if (proj != null) {
          final boxH = (m.heightM * proj.scale * 1.4).clamp(18.0, 92.0);
          final boxW = (18.0 * proj.scale).clamp(10.0, 38.0);
          final rect = Rect.fromLTWH(
            proj.offset.dx - boxW / 2,
            proj.offset.dy - boxH,
            boxW,
            boxH,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()
              ..color = const Color(0xFFF59E0B).withValues(alpha: 0.28)
              ..style = PaintingStyle.fill,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()
              ..color = const Color(0xFFFBBF24).withValues(alpha: 0.90)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke,
          );
          _drawLabelNonOverlapping(
            canvas,
            m.name,
            Offset(proj.offset.dx, rect.top - 10),
            const Color(0xFFFDE68A),
            placedLabels,
          );
        }
      }

      // 3. Feux, échangeurs, ralentisseurs (`RoadFeature`)
      for (final rf in scene.roadFeatures) {
        final local = _toLocalMeters(rf.latitude, rf.longitude);
        final proj = _project(size, local.dx, local.dy);
        if (proj != null) {
          final color = rf.kind == 'traffic_signal'
              ? const Color(0xFFEF4444)
              : (rf.kind == 'interchange'
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFFF59E0B));
          final r = (10.0 * proj.scale).clamp(4.0, 12.0);
          canvas.drawCircle(
            proj.offset,
            r * 1.8,
            Paint()..color = color.withValues(alpha: 0.26),
          );
          canvas.drawCircle(
            proj.offset,
            r,
            Paint()..color = color,
          );
          if (rf.distanceM <= 240) {
            _drawLabelNonOverlapping(
              canvas,
              '${rf.name} (${rf.distanceM.round()}m)',
              Offset(proj.offset.dx, proj.offset.dy - 14),
              Colors.white,
              placedLabels,
            );
          }
        }
      }

      // 4. Trafic en direct (véhicules sur la chaussée devant soi)
      for (final seg in scene.trafficSegments) {
        final local = _toLocalMeters(seg.latitude, seg.longitude);
        final proj = _project(size, local.dx.clamp(-8.0, 8.0), local.dy);
        if (proj != null) {
          final carW = (18.0 * proj.scale).clamp(8.0, 32.0);
          final carH = (11.0 * proj.scale).clamp(6.0, 20.0);
          final carColor = seg.congestionLevel == 'heavy'
              ? const Color(0xFFEF4444)
              : const Color(0xFF94A3B8);
          final rect = Rect.fromCenter(
            center: Offset(proj.offset.dx, proj.offset.dy - carH * 0.5),
            width: carW,
            height: carH,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()..color = carColor.withValues(alpha: 0.88),
          );
        }
      }
    }

    // 5. Signalements communautaires actifs
    for (final rep in activeReports) {
      final local = _toLocalMeters(rep.latitude, rep.longitude);
      final proj = _project(size, local.dx, local.dy);
      if (proj != null) {
        canvas.drawCircle(
          proj.offset,
          9.0 * proj.scale.clamp(0.5, 1.3),
          Paint()..color = const Color(0xFFEF4444),
        );
        _drawLabelNonOverlapping(
          canvas,
          rep.label,
          Offset(proj.offset.dx, proj.offset.dy - 14),
          const Color(0xFFFCA5A5),
          placedLabels,
        );
      }
    }
  }

  void _drawEgoVehicle(Canvas canvas, Offset center) {
    final mode = transportMode.toLowerCase();
    // Aura néon au sol sous le véhicule
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 78, height: 30),
      Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.28),
    );

    if (mode == 'motorcycle' || mode == 'moto' || mode == 'bicycle' || mode == 'velo') {
      // Silhouette 3D stylisée Moto / Deux-roues vue arrière 3/4
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy - 16), width: 22, height: 42),
        const Radius.circular(10),
      );
      canvas.drawRRect(
        body,
        Paint()..color = const Color(0xFF0F172A),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..color = const Color(0xFF38BDF8)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
      // Feu arrière rouge & phare avant blanc
      canvas.drawCircle(
        Offset(center.dx, center.dy - 1),
        3.5,
        Paint()..color = const Color(0xFFEF4444),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(center.dx, center.dy - 46), width: 32, height: 22),
        Paint()..color = const Color(0xFFE0F2FE).withValues(alpha: 0.25),
      );
    } else if (mode == 'foot' || mode == 'walk' || mode == 'pedestrian') {
      canvas.drawCircle(
        Offset(center.dx, center.dy - 14),
        14,
        Paint()..color = const Color(0xFF10B981),
      );
      canvas.drawCircle(
        Offset(center.dx, center.dy - 14),
        14,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    } else {
      final carRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy - 16), width: 46, height: 54),
        const Radius.circular(12),
      );
      canvas.drawRRect(
        carRect,
        Paint()..color = const Color(0xFF0B1F3A),
      );
      canvas.drawRRect(
        carRect,
        Paint()
          ..color = const Color(0xFFE0F2FE)
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(center.dx, center.dy - 15), width: 32, height: 26),
          const Radius.circular(7),
        ),
        Paint()..color = const Color(0xFF1E3A5F),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(center.dx - 14, center.dy + 7), width: 9, height: 3.5),
        Paint()..color = const Color(0xFFEF4444),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(center.dx + 14, center.dy + 7), width: 9, height: 3.5),
        Paint()..color = const Color(0xFFEF4444),
      );
    }
  }

  void _drawLabelNonOverlapping(
    Canvas canvas,
    String text,
    Offset pos,
    Color color,
    List<Rect> occupied,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 160);

    final rect = Rect.fromLTWH(
      pos.dx - tp.width / 2 - 4,
      pos.dy - tp.height / 2 - 2,
      tp.width + 8,
      tp.height + 4,
    );
    if (occupied.any((r) => r.overlaps(rect))) {
      return;
    }
    occupied.add(rect);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FasoRadarPainter oldDelegate) => true;
}
