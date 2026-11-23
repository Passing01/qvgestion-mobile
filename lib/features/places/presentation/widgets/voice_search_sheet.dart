import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:latlong2/latlong.dart';
import 'package:qvgestion_mobile/core/config/app_config.dart';
import 'package:qvgestion_mobile/core/debug/debug_info.dart';
import 'package:qvgestion_mobile/core/errors/app_error_reporter.dart';
import 'package:qvgestion_mobile/core/services/voice_asr_service.dart';
import 'package:qvgestion_mobile/core/theme/app_colors.dart';
import 'package:qvgestion_mobile/core/utils/app_logger.dart';
import 'package:qvgestion_mobile/features/places/data/models/place_model.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';

/// Modal interactive de recherche vocale en Mooré, Dioula et Français
class VoiceSearchSheet extends ConsumerStatefulWidget {
  const VoiceSearchSheet({super.key});

  static Future<PlaceModel?> show(BuildContext context) {
    return showModalBottomSheet<PlaceModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (context) => const VoiceSearchSheet(),
    );
  }

  @override
  ConsumerState<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends ConsumerState<VoiceSearchSheet>
    with SingleTickerProviderStateMixin {
  late final stt.SpeechToText _speech;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _isListening = false;
  bool _isRecordingAsr = false;
  bool _isTranscribingAsr = false;
  String _spokenText = '';
  String _selectedLanguage = 'fr'; // 'mos', 'diu', 'fr'
  String _statusMessage = 'Appuyez pour parler en Mooré, Dioula ou Français';

  AudioRecorder? _asrRecorder;
  StreamSubscription<Uint8List>? _asrStreamSub;
  BytesBuilder _pcmBuilder = BytesBuilder(copy: false);
  Timer? _asrAutoStopTimer;

  bool get _isUnderWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  String _langDisplayName(String code) {
    switch (code) {
      case 'mos':
        return 'Mooré';
      case 'diu':
        return 'Dioula';
      default:
        return 'Français';
    }
  }

  final List<Map<String, dynamic>> _quickVoicePrompts = [
    {
      'label': 'Grand Marché Rood-Woko',
      'query': 'Rood-Woko',
      'lat': 12.3685,
      'lon': -1.5222,
      'quartier': 'Centre-Ville',
    },
    {
      'label': 'Héros Nationaux',
      'query': 'Héros Nationaux',
      'lat': 12.312187,
      'lon': -1.502617,
      'quartier': 'Ouaga 2000',
    },
    {
      'label': 'CHU Yalgado Ouédraogo',
      'query': 'CHU Yalgado',
      'lat': 12.3833115,
      'lon': -1.5062033,
      'quartier': 'Dapoya',
    },
    {
      'label': 'Pharmacie de garde',
      'query': 'Pharmacie',
      'lat': 12.3850,
      'lon': -1.5020,
      'quartier': 'Somgandé',
    },
    {
      'label': 'Station-Service',
      'query': 'Station',
      'lat': 12.3710,
      'lon': -1.5180,
      'quartier': 'Avenue Bassawarga',
    },
    {
      'label': 'Échangeur du Nord',
      'query': 'Échangeur du Nord',
      'lat': 12.384738,
      'lon': -1.554870,
      'quartier': 'Tampouy',
    },
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Démarrer automatiquement l'écoute vocale
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
    });
  }

  @override
  void dispose() {
    _asrAutoStopTimer?.cancel();
    _asrStreamSub?.cancel();
    _asrRecorder?.dispose();
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (_isUnderWidgetTest || _isTranscribingAsr) return;

    await _cancelActiveCapture();

    // Mooré & Dioula passent par l'ASR neuronal backend (facebook/mms-1b-all)
    if (_selectedLanguage == 'mos' || _selectedLanguage == 'diu') {
      await _startAsrRecording();
      return;
    }

    try {
      if (!kIsWeb) {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _statusMessage =
                  'Microphone non autorisé. Vous pouvez choisir un lieu ci-dessous :';
            });
          }
          return;
        }
      }

      final available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            setState(() {
              if (status == 'listening') {
                _isListening = true;
                _statusMessage = 'Écoute en cours... Dites votre destination';
              } else if (status == 'notListening' || status == 'done') {
                _isListening = false;
                if (_spokenText.isEmpty) {
                  _statusMessage =
                      'Touchez le micro pour réessayer ou choisissez ci-dessous';
                }
              }
            });
          }
        },
        onError: (errorNotification) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _statusMessage =
                  'Micro prêt. Touchez le bouton pour dicter ou sélectionnez un lieu.';
            });
          }
        },
      );

      if (available) {
        if (mounted) {
          setState(() {
            _isListening = true;
            _spokenText = '';
            _statusMessage = 'Je vous écoute... Parlez distinctement';
          });
        }

        await _speech.listen(
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            localeId: 'fr_FR',
          ),
          onResult: (result) {
            AppLogger.i("[VOIX-REC] entendu='${result.recognizedWords}' final=${result.finalResult}");
            if (mounted) {
              setState(() {
                _spokenText = result.recognizedWords;
              });

              if (result.finalResult && _spokenText.isNotEmpty) {
                _processSpokenText(_spokenText);
              }
            }
          },
        );
      } else {
        // Repli sur l'enregistreur ASR serveur si la reconnaissance navigateur n'est pas disponible
        await _startAsrRecording();
      }
    } catch (e) {
      AppLogger.w('Erreur d\'écoute vocale: $e');
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusMessage =
              'Sélectionnez un lieu ou prononcez votre destination :';
        });
      }
    }
  }

  Future<void> _cancelActiveCapture() async {
    _asrAutoStopTimer?.cancel();
    _asrAutoStopTimer = null;
    if (_isRecordingAsr) {
      try {
        await _asrStreamSub?.cancel();
        await _asrRecorder?.stop();
      } catch (_) {}
      _isRecordingAsr = false;
    }
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> _startAsrRecording() async {
    try {
      if (!kIsWeb) {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _isRecordingAsr = false;
              _statusMessage =
                  'Permission micro refusée. Choisissez un lieu ci-dessous :';
            });
          }
          return;
        }
      }

      final recorder = _asrRecorder ??= AudioRecorder();
      final permitted = await recorder.hasPermission();
      if (!permitted) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _isRecordingAsr = false;
            _statusMessage =
                'Microphone inaccessible dans ce navigateur. Choisissez ci-dessous :';
          });
        }
        return;
      }

      _pcmBuilder = BytesBuilder(copy: false);
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _asrStreamSub = stream.listen(
        (chunk) => _pcmBuilder.add(chunk),
        onError: (Object err) => AppLogger.w('[VOIX-ASR] Erreur flux audio: $err'),
      );

      if (mounted) {
        setState(() {
          _isListening = true;
          _isRecordingAsr = true;
          _spokenText = '';
          _statusMessage =
              'Parlez en ${_langDisplayName(_selectedLanguage)}... Touchez le micro pour envoyer';
        });
      }

      _asrAutoStopTimer?.cancel();
      _asrAutoStopTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && _isRecordingAsr) {
          _stopAndTranscribeAsr();
        }
      });
    } catch (e) {
      AppLogger.w('Erreur démarrage enregistrement ASR: $e');
      if (mounted) {
        setState(() {
          _isListening = false;
          _isRecordingAsr = false;
          _statusMessage =
              'Micro prêt. Touchez le bouton ou sélectionnez un lieu :';
        });
      }
    }
  }

  Future<void> _stopAndTranscribeAsr() async {
    _asrAutoStopTimer?.cancel();
    _asrAutoStopTimer = null;
    if (!_isRecordingAsr) return;

    try {
      await _asrRecorder?.stop();
    } catch (e) {
      AppLogger.w('Erreur arrêt recorder ASR: $e');
    }
    try {
      await _asrStreamSub?.cancel();
    } catch (_) {}
    _asrStreamSub = null;
    _isRecordingAsr = false;

    final pcmBytes = _pcmBuilder.takeBytes();
    if (pcmBytes.length < 3200) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusMessage =
              'Audio trop court. Touchez le micro et parlez plus distinctement.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isListening = false;
        _isTranscribingAsr = true;
        _statusMessage =
            'Analyse vocale ${_langDisplayName(_selectedLanguage)} (MMS)...';
      });
    }

    try {
      final wavBytes = VoiceAsrService.wrapPcm16AsWav(pcmBytes);
      final text = await ref
          .read(voiceAsrServiceProvider)
          .transcribeWavBytes(wavBytes, lang: _selectedLanguage);
      if (!mounted) return;
      setState(() {
        _isTranscribingAsr = false;
        _spokenText = text;
        if (text.isEmpty) {
          _statusMessage =
              'Aucun mot reconnu. Réessayez ou choisissez un lieu :';
        }
      });
      if (text.isNotEmpty) {
        _processSpokenText(text);
      }
    } catch (e) {
      AppLogger.w('Échec transcription ASR ($_selectedLanguage): $e');
      if (mounted) {
        setState(() {
          _isTranscribingAsr = false;
          _statusMessage =
              'Reconnaissance vocale ${_langDisplayName(_selectedLanguage)} indisponible. Réessayez ou choisissez un lieu :';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    if (_isRecordingAsr) {
      await _stopAndTranscribeAsr();
      return;
    }
    try {
      await _speech.stop();
    } catch (e) {
      AppLogger.w('Erreur arrêt de l\'écoute vocale: $e');
    }
    if (mounted) {
      setState(() => _isListening = false);
    }
    if (_spokenText.isNotEmpty) {
      _processSpokenText(_spokenText);
    }
  }

  void _processSpokenText(String text) async {
    final query = text.toLowerCase().trim();
    if (query.isEmpty) return;

    // 1. Recherche via le repository universel
    try {
      final repo = ref.read(placesRepositoryProvider);
      final loc = ref.read(currentLocationProvider);
      final searchRes = await repo.searchUniversal(
        query: text,
        currentLat: loc.lat,
        currentLon: loc.lon,
        limit: 5,
      );

      if (searchRes.places.isNotEmpty) {
        _selectPlace(place: searchRes.places.first);
        return;
      }
    } catch (_) {}

    // 2. Chercher dans les suggestions rapides de la modal
    for (final item in _quickVoicePrompts) {
      final label = (item['label'] as String).toLowerCase();
      final q = (item['query'] as String).toLowerCase();
      if (query.contains(q) || query.contains(label)) {
        _selectPlace(
          name: item['label'] as String,
          lat: item['lat'] as double,
          lon: item['lon'] as double,
          quartier: item['quartier'] as String,
        );
        return;
      }
    }

    // 3. Si non trouvé : définir la requête et renvoyer vers la recherche textuelle
    ref.read(searchQueryProvider.notifier).setQuery(text);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectPlace({
    PlaceModel? place,
    String? name,
    double? lat,
    double? lon,
    String? quartier,
  }) async {
    try {
      await _speech.stop();
    } catch (e) {
      AppLogger.w('Erreur arrêt speech: $e');
    }

    if (!mounted) return;

    if (place == null && (lat == null || lon == null)) {
      if (!AppConfig.testMode) {
        AppErrorReporter.reportError('Coordonnées invalides pour ce lieu', tag: 'Recherche');
        return;
      }
    }

    final resolvedPlace = place ??
        PlaceModel(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          nom: name ?? 'Destination sélectionnée',
          categorieId: 1,
          latitude: lat ?? 12.3685,
          longitude: lon ?? -1.5222,
          quartier: quartier ?? 'Ouagadougou',
        );

    DebugInfo.instance.setDestination(
      LatLng(resolvedPlace.latitude, resolvedPlace.longitude),
      source: 'recherche',
    );
    Navigator.of(context).pop(resolvedPlace);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 25,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée de glissement
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),

              // Titre et sélecteur de langue locale
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Recherche Vocale Locale',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Consignes et reconnaissance en langues du Faso',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sélecteur de langue vocale (Mooré, Dioula, Français)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLangChip(code: 'mos', label: '🇧🇫 Mooré'),
                  const SizedBox(width: 8),
                  _buildLangChip(code: 'diu', label: '🇧🇫 Dioula'),
                  const SizedBox(width: 8),
                  _buildLangChip(code: 'fr', label: '🇫🇷 Français'),
                ],
              ),
              const SizedBox(height: 28),

              // Bouton Micro animé avec halo d'écoute
              GestureDetector(
                onTap: () {
                  if (_isTranscribingAsr) return;
                  if (_isListening) {
                    _stopListening();
                  } else {
                    _startListening();
                  }
                },
                child: ScaleTransition(
                  scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
                            : [AppColors.primary, const Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? Colors.red : AppColors.primary)
                              .withValues(alpha: 0.35),
                          blurRadius: _isListening ? 26 : 14,
                          spreadRadius: _isListening ? 6 : 1,
                        ),
                      ],
                    ),
                    child: _isTranscribingAsr
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Message d'état ou texte transcrit
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _spokenText.isNotEmpty ? '« $_spokenText »' : _statusMessage,
                  key: ValueKey(_spokenText.isNotEmpty ? _spokenText : _statusMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _spokenText.isNotEmpty ? 17 : 13,
                    fontWeight: _spokenText.isNotEmpty ? FontWeight.bold : FontWeight.w600,
                    color: _spokenText.isNotEmpty ? AppColors.primary : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Suggestions de destinations rapides au Faso
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Suggestions de destinations à Ouaga :',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickVoicePrompts.map((p) {
                  return ActionChip(
                    avatar: const Icon(Icons.place_rounded, size: 16, color: AppColors.primary),
                    label: Text(
                      p['label'] as String,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: () {
                      _selectPlace(
                        name: p['label'] as String,
                        lat: p['lat'] as double,
                        lon: p['lon'] as double,
                        quartier: p['quartier'] as String,
                      );
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLangChip({required String code, required String label}) {
    final isSelected = _selectedLanguage == code;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedLanguage = code);
        _startListening();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
