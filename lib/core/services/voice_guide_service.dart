import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:qvgestion_mobile/core/config/env_config.dart';
import 'package:qvgestion_mobile/core/services/navigation_engine.dart';
import 'package:qvgestion_mobile/core/utils/app_logger.dart';
import 'package:qvgestion_mobile/features/guidance/data/models/enriched_route_model.dart';
import 'package:qvgestion_mobile/features/places/data/models/place_model.dart';
import 'package:qvgestion_mobile/features/routes/data/models/route_model.dart';

/// Étape ou virage associé à sa position curviligne sur le tracé réel (Étape 9)
class GuideStep {
  final int order;
  final double along; // Mètres cumulés depuis l'origine du tracé
  final String instruction;
  final String maneuverType; // 'turn_left', 'turn_right', 'slight_left', 'roundabout', 'straight', 'arrive', 'depart'
  final String? streetName;
  final double distanceMeters;
  final int confidence; // 3 = relevé terrain, 2 = source ouverte, 1 = consigne simple sans repère
  final String? anchorName;
  final String? anchorType; // 'traffic_signal', 'bridge', 'interchange', 'roundabout', 'place'
  final String? anchorSide; // 'left', 'right', 'ahead'
  final String? nameTts; // Correction phonétique pour synthèse vocale
  final String? localAudioFile; // Chemin fichier audio pour langues nationales

  const GuideStep({
    required this.order,
    required this.along,
    required this.instruction,
    required this.maneuverType,
    this.streetName,
    this.distanceMeters = 0.0,
    this.confidence = 1,
    this.anchorName,
    this.anchorType,
    this.anchorSide,
    this.nameTts,
    this.localAudioFile,
  });

  /// Formule la consigne à prononcer à [dist] mètres avant le virage
  String spoken({required double dist, String language = 'fr'}) {
    final lang = language.toLowerCase();
    if (lang == 'mos' || lang == 'moore') {
      return _spokenMoore(dist);
    } else if (lang == 'diu' || lang == 'dioula') {
      return _spokenDioula(dist);
    }
    return _spokenFr(dist);
  }

  /// Résout l'URL de synthèse vocale neuronale dynamique (sans lire de fichiers figés)
  String neuralTtsUrl({required double dist, String language = 'fr'}) {
    final lang = _normalizeLang(language);
    final text = spoken(dist: dist, language: lang);
    final frFallback = spoken(dist: dist, language: 'fr');
    return buildNeuralTtsUrl(text: text, language: lang, frenchFallback: frFallback);
  }

  /// Construit l'URL du flux TTS neuronal backend pour n'importe quelle phrase
  static String buildNeuralTtsUrl({
    required String text,
    String language = 'fr',
    String? frenchFallback,
  }) {
    final lang = _normalizeLang(language);
    final base = EnvConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final qp = <String, String>{
      'lang': lang,
      'text': text,
      if (frenchFallback != null && frenchFallback.isNotEmpty)
        'fallback_fr': frenchFallback,
    };
    return Uri.parse('$base/guidance/tts').replace(queryParameters: qp).toString();
  }

  static String _normalizeLang(String language) {
    final l = language.toLowerCase().trim();
    if (l == 'mos' || l == 'moore') return 'mos';
    if (l == 'diu' || l == 'dioula') return 'diu';
    return 'fr';
  }

  /// Arrondi canonique partagé entre l'affichage écran et les annonces vocales
  /// pour garantir une cohérence parfaite du métrage.
  static double alignedDisplayMeters(double rawMeters) {
    if (!rawMeters.isFinite || rawMeters <= 0) return 0.0;
    if (rawMeters >= 1000.0) return (rawMeters / 100.0).round() * 100.0;
    if (rawMeters >= 190.0 && rawMeters <= 210.0) return 200.0;
    if (rawMeters >= 100.0) return (rawMeters / 10.0).round() * 10.0;
    if (rawMeters >= 40.0 && rawMeters <= 58.0) return 50.0;
    if (rawMeters >= 30.0) return (rawMeters / 5.0).round() * 5.0;
    return rawMeters.roundToDouble();
  }

  /// Résout la source audio pour cette distance et cette langue.
  /// Privilégie la voix neuronale dynamique (/guidance/tts) plutôt que les fichiers WhatsApp statiques.
  String? audioFor({required double dist, String language = 'fr'}) {
    if (localAudioFile != null && localAudioFile!.isNotEmpty) {
      return localAudioFile;
    }
    return neuralTtsUrl(dist: dist, language: language);
  }

  /// Icône Material symbolisant le virage ou l'action
  IconData get iconData {
    switch (maneuverType.toLowerCase()) {
      case 'turn_left':
      case 'left':
      case 'sharp_left':
        return Icons.turn_left_rounded;
      case 'turn_right':
      case 'right':
      case 'sharp_right':
        return Icons.turn_right_rounded;
      case 'slight_left':
        return Icons.turn_slight_left_rounded;
      case 'slight_right':
        return Icons.turn_slight_right_rounded;
      case 'roundabout':
        return Icons.change_circle_rounded;
      case 'u_turn':
        return Icons.u_turn_left_rounded;
      case 'arrive':
        return Icons.flag_rounded;
      case 'depart':
        return Icons.navigation_rounded;
      case 'straight':
      default:
        return Icons.straight_rounded;
    }
  }

  String _spokenFr(double dist) {
    final effectiveAnchor = nameTts ?? anchorName;
    final dInt = dist.toInt();
    final distPhrase = dist >= 1000.0
        ? '${(dist / 1000.0).toStringAsFixed(1)} km'
        : '$dInt mètres';
    final action = _actionFr(maneuverType);

    if (maneuverType == 'arrive') {
      return dist >= 100.0
          ? 'Dans $distPhrase, vous arriverez à destination'
          : 'Vous arrivez à destination';
    }
    if (maneuverType == 'depart') {
      return 'Prenez la route';
    }

    // 9b · Narrateur local : repères réels (confiance >= 2)
    if (confidence >= 2 && effectiveAnchor != null && effectiveAnchor.isNotEmpty) {
      if (anchorType == 'traffic_signal' || anchorType == 'feu') {
        return dist >= 100.0
            ? 'Dans $distPhrase, au feu, $action'
            : 'Au feu, $action';
      } else {
        return dist >= 100.0
            ? 'Dans $distPhrase, après $effectiveAnchor, $action'
            : 'Après $effectiveAnchor, $action';
      }
    }

    // 9a · Consigne simple du moteur sans repère (confiance 1)
    if (streetName != null &&
        streetName!.isNotEmpty &&
        !streetName!.toLowerCase().startsWith('unnamed')) {
      return 'Dans $distPhrase, $action sur $streetName';
    }
    return 'Dans $distPhrase, $action';
  }

  String _spokenMoore(double dist) {
    final effectiveAnchor = nameTts ?? anchorName ?? '';
    final action = _actionMoore(maneuverType);

    if (maneuverType == 'arrive') {
      return 'Y taame y zĩigẽ';
    }
    if (maneuverType == 'depart') {
      return 'Rɩk sorã';
    }

    final distPhrase = dist >= 1000.0
        ? 'Kilomɛtr ${(dist / 1000.0).round()}'
        : 'Mɛtr ${dist.toInt()}';

    if (confidence >= 2 && effectiveAnchor.isNotEmpty) {
      if (anchorType == 'traffic_signal' || anchorType == 'feu') {
        return dist >= 100.0
            ? '$distPhrase poore, feu wã nengẽ, $action'
            : 'Feu wã nengẽ, $action';
      } else {
        return dist >= 100.0
            ? '$distPhrase poore, $effectiveAnchor poore, $action'
            : '$effectiveAnchor poore, $action';
      }
    }

    return dist >= 100.0
        ? '$distPhrase poore, $action'
        : 'Taore mɛtr ${dist.toInt()}, $action';
  }

  /// Asset audio humain natif en Mooré enregistré localement (fallback garanti si TTS neuronal indisponible)
  static String? nativeAssetFor({
    required String language,
    required String maneuverType,
    String textHint = '',
  }) {
    final lang = language.toLowerCase();
    if (lang != 'mos' && lang != 'moore' && lang != 'diu' && lang != 'dioula') {
      return null;
    }
    if (lang == 'diu' || lang == 'dioula') {
      return null;
    }
    final t = maneuverType.toLowerCase();
    final h = textHint.toLowerCase();
    if (t == 'arrive' || h.contains('taame') || h.contains('arriv')) {
      return 'assets/audio/mos/arrive.ogg';
    }
    if (t == 'depart' || h.contains('départ') || h.contains('rɩk sorã') && !h.contains('rond-point')) {
      return 'assets/audio/mos/depart.ogg';
    }
    if (t.contains('left') || h.contains('goabga') || h.contains('gauche')) {
      return 'assets/audio/mos/turn_left.ogg';
    }
    if (t.contains('right') || h.contains('rɩtgo') || h.contains('droite')) {
      return 'assets/audio/mos/turn_right.ogg';
    }
    return 'assets/audio/mos/straight.ogg';
  }

  String _spokenDioula(double dist) {
    final effectiveAnchor = nameTts ?? anchorName ?? '';
    final action = _actionDioula(maneuverType);

    if (maneuverType == 'arrive') {
      return 'I sera i yɔrɔ la';
    }
    if (maneuverType == 'depart') {
      return 'Sira ta';
    }

    final distPhrase = dist >= 1000.0
        ? 'Kilomɛtɛrɛ ${(dist / 1000.0).round()}'
        : 'Mɛtɛrɛ ${dist.toInt()}';

    if (confidence >= 2 && effectiveAnchor.isNotEmpty) {
      if (anchorType == 'traffic_signal' || anchorType == 'feu') {
        return dist >= 100.0
            ? '$distPhrase kɔfɛ, feu yɔrɔ la, $action'
            : 'Feu yɔrɔ la, $action';
      } else {
        return dist >= 100.0
            ? '$distPhrase kɔfɛ, $effectiveAnchor kɔfɛ, $action'
            : '$effectiveAnchor kɔfɛ, $action';
      }
    }

    return dist >= 100.0
        ? '$distPhrase kɔfɛ, $action'
        : 'Ta ɲɛfɛ mɛtɛrɛ ${dist.toInt()}, ka $action';
  }

  static String _actionFr(String type) {
    switch (type.toLowerCase()) {
      case 'turn_left':
      case 'left':
        return 'tournez à gauche';
      case 'turn_right':
      case 'right':
        return 'tournez à droite';
      case 'slight_left':
        return 'serrez à gauche';
      case 'slight_right':
        return 'serrez à droite';
      case 'sharp_left':
        return 'tournez franchement à gauche';
      case 'sharp_right':
        return 'tournez franchement à droite';
      case 'u_turn':
        return 'faites demi-tour';
      case 'roundabout':
        return 'au rond-point, prenez la sortie';
      case 'straight':
        return 'continuez tout droit';
      default:
        return 'suivez la route';
    }
  }

  static String _actionMoore(String type) {
    switch (type.toLowerCase()) {
      case 'turn_left':
      case 'left':
      case 'slight_left':
      case 'sharp_left':
        return 'gilli wĩndg-goabga';
      case 'turn_right':
      case 'right':
      case 'slight_right':
      case 'sharp_right':
        return 'gilli wĩndg-rɩtgo';
      case 'roundabout':
        return 'rond-point wã zugu, rɩk sorã';
      case 'straight':
      default:
        return 'kẽng tɩrga';
    }
  }

  static String _actionDioula(String type) {
    switch (type.toLowerCase()) {
      case 'turn_left':
      case 'left':
      case 'slight_left':
      case 'sharp_left':
        return 'kɛlɛbili numanya fɛ';
      case 'turn_right':
      case 'right':
      case 'slight_right':
      case 'sharp_right':
        return 'kɛlɛbili kinin fɛ';
      case 'roundabout':
        return 'rond-point kan, sira ta';
      case 'straight':
      default:
        return 'taga ɲɛfɛ';
    }
  }
}

/// Service de synthèse vocale et d'affichage de bandeau conforme Étape 9
class VoiceGuide {
  VoiceGuide({FlutterTts? tts, AudioPlayer? player})
      : _customTts = tts,
        _customPlayer = player;

  final FlutterTts? _customTts;
  final AudioPlayer? _customPlayer;
  FlutterTts? _ttsInstance;
  AudioPlayer? _playerInstance;

  FlutterTts get _tts => _customTts ?? (_ttsInstance ??= FlutterTts());
  AudioPlayer? get _player {
    if (_customPlayer != null) return _customPlayer;
    if (_playerInstance != null) return _playerInstance;
    try {
      _playerInstance = AudioPlayer();
      return _playerInstance;
    } catch (e) {
      AppLogger.w('Initialisation AudioPlayer impossible: $e');
      return null;
    }
  }

  bool _ok = false;
  bool get isOk => _ok;
  int _speakSeq = 0;

  /// Cache mémoire de session pour rejeu instantané (< 5 ms) des audios TTS générés
  final Map<String, Uint8List> _memAudioCache = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inFlightAudio =
      <String, Future<Uint8List?>>{};

  /// Bandeau de consigne toujours affiché en gros à l'écran
  final banner = ValueNotifier<String>('');

  void clearBanner() {
    _speakSeq++;
    banner.value = '';
  }

  Future<void> init() async {
    clearBanner();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest && _customTts == null) {
      _ok = false;
      return;
    }
    try {
      final res = await _tts
          .isLanguageAvailable('fr-FR')
          .timeout(const Duration(milliseconds: 400), onTimeout: () => false);
      _ok = res == true;
      if (_ok) {
        await _tts.setLanguage('fr-FR');
        await _tts.setSpeechRate(0.48);
        await _tts.awaitSpeakCompletion(true);
      } else {
        AppLogger.w('[VOIX] fr-FR indisponible : texte seul');
      }
    } catch (e) {
      _ok = false;
      AppLogger.w('[VOIX] fr-FR indisponible : texte seul ($e)');
    }
  }

  /// Énonce la consigne à voix haute et met à jour le bandeau textuel
  Future<void> say(
    String text, {
    String? audioSource,
    String language = 'fr',
    String? frenchFallbackText,
    String maneuverType = '',
  }) async {
    final mySeq = ++_speakSeq;
    AppLogger.i('[VOIX] $text');
    banner.value = text; // Le texte s'affiche toujours

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    final effectiveAudioSource = (audioSource != null && audioSource.isNotEmpty)
        ? _resolveAudioSourceUrl(audioSource)
        : (!isTest
            ? GuideStep.buildNeuralTtsUrl(
                text: text,
                language: language,
                frenchFallback: frenchFallbackText,
              )
            : null);

    bool audioPlayed = false;
    // Lecture du flux audio neuronal dynamique (ou source locale explicite)
    if (effectiveAudioSource != null && effectiveAudioSource.isNotEmpty && (!isTest || _customPlayer != null)) {
      try {
        await _tts.stop();
        final player = _player;
        if (player != null) {
          await player.stop();
          if (effectiveAudioSource.startsWith('assets/')) {
            if (_speakSeq != mySeq) return;
            await player.play(AssetSource(effectiveAudioSource.replaceFirst('assets/', '')));
            audioPlayed = true;
          } else if (effectiveAudioSource.startsWith('http')) {
            final bytes = await _fetchAudioBytesIfReady(effectiveAudioSource);
            if (_speakSeq != mySeq) return; // Annulé si une annonce plus récente a remplacé celle-ci
            if (bytes != null && bytes.isNotEmpty) {
              await player.play(BytesSource(bytes));
              audioPlayed = true;
            }
          } else {
            if (_speakSeq != mySeq) return;
            await player.play(DeviceFileSource(effectiveAudioSource));
            audioPlayed = true;
          }
        }
      } catch (e) {
        AppLogger.w('[VOIX] Échec lecture audio neuronal ($e), repli vocal');
        audioPlayed = false;
      }
    }

    if (_speakSeq != mySeq) return;

    // Repli vocal humain Mooré natif enregistré si le serveur TTS Mooré renvoie 503 / est hors ligne
    if (!audioPlayed && (!isTest || _customPlayer != null)) {
      final nativeAsset = GuideStep.nativeAssetFor(
        language: language,
        maneuverType: maneuverType,
        textHint: '$text ${frenchFallbackText ?? ''}',
      );
      if (nativeAsset != null) {
        try {
          final player = _player;
          if (player != null) {
            await _tts.stop();
            await player.stop();
            await player.play(AssetSource(nativeAsset.replaceFirst('assets/', '')));
            audioPlayed = true;
          }
        } catch (e) {
          AppLogger.w('[VOIX] Échec lecture audio natif Mooré ($e)');
        }
      }
    }

    // Synthèse vocale TTS :
    // RÈGLE ÉTAPE 10 : En Mooré/Dioula, ne jamais prononcer la phonétique Mooré avec une voix TTS française.
    if (!audioPlayed && _ok) {
      try {
        await _player?.stop();
        await _tts.stop();
        final textToSpeak = (language != 'fr' && language != 'fr-FR')
            ? (frenchFallbackText != null && frenchFallbackText.isNotEmpty ? frenchFallbackText : text)
            : text;
        await _tts.speak(textToSpeak);
      } catch (e) {
        AppLogger.w('[VOIX] Erreur synthèse vocale: $e');
      }
    }
  }

  Future<Uint8List?> _fetchAudioBytesIfReady(String url) {
    final cached = _memAudioCache[url];
    if (cached != null && cached.isNotEmpty) {
      return Future<Uint8List?>.value(cached);
    }
    return _inFlightAudio.putIfAbsent(url, () async {
      try {
        return await _fetchAudioBytesUncached(url);
      } finally {
        _inFlightAudio.remove(url);
      }
    });
  }

  Future<Uint8List?> _fetchAudioBytesUncached(String url) async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.bytes,
        connectTimeout: const Duration(milliseconds: 5000),
        receiveTimeout: const Duration(milliseconds: 25000),
        validateStatus: (status) => status == 200,
      ),
    );
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await dio.get<List<int>>(url);
          final raw = res.data;
          if (res.statusCode == 200 && raw != null && raw.length > 64) {
            final bytes = Uint8List.fromList(raw);
            if (_memAudioCache.length >= 160) {
              _memAudioCache.remove(_memAudioCache.keys.first);
            }
            _memAudioCache[url] = bytes;
            return bytes;
          }
          return null;
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (attempt == 0 && (code == 503 || code == 502 || code == 504)) {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            continue;
          }
          rethrow;
        }
      }
      return null;
    } catch (e) {
      AppLogger.w('[VOIX] TTS distant indisponible ($e)');
      return null;
    } finally {
      dio.close();
    }
  }

  /// Pré-chauffe les prochaines consignes séquentiellement pour ne pas saturer ZeroGPU.
  Future<void> prefetchSteps(
    List<GuideStep> steps, {
    required String language,
    int startIndex = 0,
    int maxSteps = 6,
  }) async {
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest || steps.isEmpty || startIndex >= steps.length) return;

    final langNorm = language.toLowerCase().trim();
    if (langNorm != 'mos' &&
        langNorm != 'moore' &&
        langNorm != 'diu' &&
        langNorm != 'dioula' &&
        langNorm != 'fr') {
      return;
    }

    final start = startIndex < 0 ? 0 : startIndex;
    final end = (start + maxSteps) < steps.length ? (start + maxSteps) : steps.length;
    final urlsToFetch = <String>[];
    for (var i = start; i < end; i++) {
      final step = steps[i];
      for (final dist in const [200.0, 50.0]) {
        final url = step.audioFor(dist: dist, language: langNorm);
        if (url != null &&
            url.startsWith('http') &&
            !_memAudioCache.containsKey(url) &&
            !urlsToFetch.contains(url)) {
          urlsToFetch.add(url);
        }
      }
    }

    for (var i = 0; i < urlsToFetch.length; i++) {
      await _fetchAudioBytesIfReady(urlsToFetch[i]);
      if (i + 1 < urlsToFetch.length) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  String _resolveAudioSourceUrl(String rawSource) {
    if (rawSource.startsWith('/api/v1/')) {
      final base = EnvConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
      return '$base${rawSource.replaceFirst('/api/v1', '')}';
    }
    if (rawSource.startsWith('/')) {
      final origin = EnvConfig.apiBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
      return '$origin$rawSource';
    }
    return rawSource;
  }

  /// Énonce la manœuvre avec prise en compte des repères familiers
  Future<void> sayStep(dynamic step, {String language = 'fr'}) async {
    String text = '';
    String frenchFallbackText = '';
    String audioUrl = '';
    String landmarkName = '';
    String maneuverType = '';

    if (step is GuideStep) {
      text = step.spoken(dist: 50.0, language: language);
      frenchFallbackText = step.spoken(dist: 50.0, language: 'fr');
      audioUrl = step.audioFor(dist: 50.0, language: language) ?? step.localAudioFile ?? '';
      landmarkName = step.anchorName ?? '';
      maneuverType = step.maneuverType;
    } else if (step is Map<String, dynamic>) {
      text = (step['localized_instruction'] as String?) ??
          (step['instruction'] as String?) ??
          (step['maneuver'] is Map ? step['maneuver']['instruction'] as String? : null) ??
          '';
      frenchFallbackText = (step['instruction'] as String?) ?? text;
      audioUrl = (step['audio_url'] as String?) ?? '';
      landmarkName = (step['landmark_name'] as String?) ?? '';
      maneuverType = (step['maneuver_type'] as String?) ??
          (step['maneuver'] is Map ? step['maneuver']['type'] as String? : null) ??
          '';
    } else {
      try {
        text = (step.localizedInstruction ?? step.originalInstruction ?? '').toString();
        frenchFallbackText = (step.originalInstruction ?? step.instruction ?? text).toString();
        audioUrl = (step.audioUrl as String?) ?? '';
        landmarkName = (step.landmarkName as String?) ?? '';
      } catch (_) {
        text = step.toString();
        frenchFallbackText = text;
      }
    }

    if (landmarkName.isNotEmpty && !text.contains(landmarkName)) {
      final lang = language.toLowerCase();
      if (lang == 'mos' || lang == 'moore') {
        text = '$landmarkName poore, $text';
      } else if (lang == 'diu' || lang == 'dioula') {
        text = '$landmarkName kɔfɛ, $text';
      } else {
        text = 'Après $landmarkName, $text';
      }
      frenchFallbackText = 'Après $landmarkName, $frenchFallbackText';
    }

    await say(
      text,
      audioSource: audioUrl.isNotEmpty ? audioUrl : null,
      language: language,
      frenchFallbackText: frenchFallbackText,
      maneuverType: maneuverType,
    );
  }

  Future<void> stop() async {
    clearBanner();
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    try {
      _tts.stop();
    } catch (_) {}
    try {
      _playerInstance?.dispose();
    } catch (_) {}
  }
}

/// Annonceur pas-à-pas le long du tracé réel (Étape 9a)
/// Annonce chaque virage à 200 m, puis à 50 m avant le virage, une seule fois chacun.
/// Fenêtre de déclenchement : 40 m.
class Announcer {
  Announcer(this.voice);

  final VoiceGuide voice;
  final _spoken = <String>{};
  DateTime? _lastSpokenAt;

  /// Clés d'annonces déjà prononcées (pour assertions et tests)
  Set<String> get spoken => Set.unmodifiable(_spoken);

  bool get hasSpokenYet => _lastSpokenAt != null;

  /// Prononce immédiatement la consigne courante (utile au démarrage de la navigation).
  void announceStepNow(
    GuideStep step, {
    required double remainingDist,
    required String language,
    DateTime? now,
  }) {
    final aligned = GuideStep.alignedDisplayMeters(remainingDist);
    final effectiveDist = aligned > 0 ? aligned : 50.0;
    _lastSpokenAt = now ?? DateTime.now();
    voice.say(
      step.spoken(dist: effectiveDist, language: language),
      audioSource: step.audioFor(dist: effectiveDist, language: language),
      language: language,
      frenchFallbackText: step.spoken(dist: effectiveDist, language: 'fr'),
      maneuverType: step.maneuverType,
    );
  }

  void onProgress(
    double along,
    List<GuideStep> steps, {
    String language = 'fr',
    int? activeStepIndex,
    bool longRangeThresholds = false,
    Duration? periodicInterval,
    DateTime? now,
  }) {
    final thresholds = longRangeThresholds
        ? const [(1000.0, 120.0), (500.0, 70.0), (200.0, 40.0), (50.0, 40.0)]
        : const [(200.0, 40.0), (50.0, 40.0)];

    bool announcedInTick = false;

    for (var i = 0; i < steps.length; i++) {
      if (activeStepIndex != null && i != activeStepIndex) continue;
      final d = steps[i].along - along; // mètres avant le virage
      if (d < 5.0) continue;

      if (longRangeThresholds) {
        if (d < 850.0) _spoken.add('$i-1000');
        if (d < 400.0) _spoken.add('$i-500');
      }
      // Évite de prononcer "200 mètres" en retard si l'usager est déjà passé sous 130 m
      if (d < 130.0) {
        _spoken.add('$i-200');
      }

      for (final (t, window) in thresholds) {
        final key = '$i-${t.toInt()}';
        if (d <= t && d > t - window && _spoken.add(key)) {
          final spokenDist = GuideStep.alignedDisplayMeters(d);
          _lastSpokenAt = now ?? DateTime.now();
          announcedInTick = true;
          voice.say(
            steps[i].spoken(dist: spokenDist, language: language),
            audioSource: steps[i].audioFor(dist: spokenDist, language: language),
            language: language,
            frenchFallbackText: steps[i].spoken(dist: spokenDist, language: 'fr'),
            maneuverType: steps[i].maneuverType,
          );
        }
      }
    }

    // Rappel vocal régulier sur les longs axes rectilignes (ex. toutes les 45 s)
    if (!announcedInTick &&
        periodicInterval != null &&
        now != null &&
        activeStepIndex != null &&
        activeStepIndex >= 0 &&
        activeStepIndex < steps.length) {
      final d = steps[activeStepIndex].along - along;
      final canRepeat = _lastSpokenAt == null ||
          now.difference(_lastSpokenAt!) >= periodicInterval;
      if (d > 260.0 && canRepeat) {
        final spokenDist = GuideStep.alignedDisplayMeters(d);
        _lastSpokenAt = now;
        voice.say(
          steps[activeStepIndex].spoken(dist: spokenDist, language: language),
          audioSource: steps[activeStepIndex].audioFor(
            dist: spokenDist,
            language: language,
          ),
          language: language,
          frenchFallbackText: steps[activeStepIndex].spoken(
            dist: spokenDist,
            language: 'fr',
          ),
          maneuverType: steps[activeStepIndex].maneuverType,
        );
      }
    }
  }

  /// Réinitialise les annonces après un recalcul d'itinéraire
  void reset() {
    _spoken.clear();
    _lastSpokenAt = null;
    voice.clearBanner();
  }
}

/// Transforme un itinéraire et sa géométrie en une séquence de [GuideStep] projetés
/// de manière strictement croissante le long du tracé réel.
List<GuideStep> buildGuideSteps({
  required RouteModel route,
  EnrichedRouteModel? enrichedRoute,
  List<PlaceModel>? places,
}) {
  final geom = RouteGeometry.fromRoute(route);
  final steps = <GuideStep>[];
  int? lastSegmentHint;
  double prevAlong = 0.0;

  final coreEnriched = (enrichedRoute != null)
      ? enrichedRoute.enrichedManeuvers
          .where((e) => e.maneuverType.toLowerCase() != 'reassurance')
          .toList()
      : const [];

  for (var i = 0; i < route.maneuvers.length; i++) {
    final m = route.maneuvers[i];
    final proj = geom.project(
      LatLng(m.location.lat, m.location.lon),
      hintSegment: lastSegmentHint,
      windowRadius: 60,
    );
    final stepAlong = proj.along >= prevAlong ? proj.along : prevAlong;
    if (proj.along >= prevAlong) {
      lastSegmentHint = proj.segmentIndex;
      prevAlong = stepAlong;
    }

    final enriched = (i < coreEnriched.length) ? coreEnriched[i] : null;

    // Correction phonétique name_tts pour les noms difficiles
    String? nameTts;
    if (enriched?.landmarkName != null && places != null) {
      for (final p in places) {
        if (p.nom.trim().toLowerCase() == enriched!.landmarkName!.trim().toLowerCase()) {
          nameTts = p.nameTts;
          break;
        }
      }
    }

    steps.add(GuideStep(
      order: m.order,
      along: stepAlong,
      instruction: enriched?.localizedInstruction ?? m.instruction,
      maneuverType: m.maneuverType,
      streetName: m.streetName,
      distanceMeters: m.distanceMeters,
      confidence: enriched?.confidence ?? 1,
      anchorName: enriched?.landmarkName,
      anchorType: enriched?.anchor?.kind,
      anchorSide: enriched?.anchor?.side,
      nameTts: nameTts,
      localAudioFile: enriched?.audioUrl,
    ));
  }

  return steps;
}

final voiceGuideProvider = Provider<VoiceGuide>((ref) {
  final guide = VoiceGuide();
  guide.init();
  ref.onDispose(() => guide.dispose());
  return guide;
});

final announcerProvider = Provider<Announcer>((ref) {
  final voice = ref.watch(voiceGuideProvider);
  return Announcer(voice);
});
