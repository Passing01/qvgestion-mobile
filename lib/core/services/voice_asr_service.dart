import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/di/core_providers.dart';
import 'package:qvgestion_mobile/core/network/api_client.dart';
import 'package:qvgestion_mobile/core/network/api_endpoints.dart';

/// Client de reconnaissance vocale (ASR) multilingue Mooré / Dioula / Français
/// relié à `POST /api/v1/guidance/asr` (`facebook/mms-1b-all`).
class VoiceAsrService {
  final ApiClient apiClient;

  VoiceAsrService(this.apiClient);

  /// Enveloppe des échantillons PCM 16 bits signés dans un en-tête WAV RIFF standard.
  static Uint8List wrapPcm16AsWav(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int channels = 1,
  }) {
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final dataLen = pcmBytes.length;
    final header = ByteData(44);

    // RIFF chunk descriptor
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataLen, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space
    header.setUint32(16, 16, Endian.little); // PCM header size
    header.setUint16(20, 1, Endian.little); // Linear PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little); // bits per sample

    // data sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataLen, Endian.little);

    final out = Uint8List(44 + dataLen);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataLen, pcmBytes);
    return out;
  }

  /// Transcrit un fichier audio WAV via le backend (`/api/v1/guidance/asr`).
  Future<String> transcribeWavBytes(
    Uint8List wavBytes, {
    String lang = 'mos',
  }) async {
    final formData = FormData.fromMap({
      'lang': lang,
      'file': MultipartFile.fromBytes(
        wavBytes,
        filename: 'voice.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
    });

    final resp = await apiClient.post<dynamic>(
      ApiEndpoints.guidanceAsr,
      data: formData,
      options: Options(
        receiveTimeout: const Duration(seconds: 35),
      ),
    );

    final data = resp.data;
    if (data is Map) {
      return (data['text'] ?? '').toString().trim();
    }
    return '';
  }
}

final voiceAsrServiceProvider = Provider<VoiceAsrService>((ref) {
  return VoiceAsrService(ref.watch(apiClientProvider));
});

