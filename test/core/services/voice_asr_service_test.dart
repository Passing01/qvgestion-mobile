import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qvgestion_mobile/core/network/api_client.dart';
import 'package:qvgestion_mobile/core/network/api_endpoints.dart';
import 'package:qvgestion_mobile/core/services/voice_asr_service.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test('wrapPcm16AsWav génère un en-tête RIFF WAVE 16kHz mono valide', () {
    final pcm = Uint8List.fromList([1, 2, 3, 4]);
    final wav = VoiceAsrService.wrapPcm16AsWav(pcm);

    expect(wav.length, 48);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(wav.sublist(44), [1, 2, 3, 4]);
  });

  test('transcribeWavBytes envoie le WAV sur /guidance/asr et retourne le texte', () async {
    final mockApi = _MockApiClient();
    when(
      () => mockApi.post<dynamic>(
        ApiEndpoints.guidanceAsr,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.guidanceAsr),
        statusCode: 200,
        data: {'text': 'rood woko', 'lang': 'mos', 'mms_lang': 'mos'},
      ),
    );

    final service = VoiceAsrService(mockApi);
    final result = await service.transcribeWavBytes(
      VoiceAsrService.wrapPcm16AsWav(Uint8List(16)),
      lang: 'mos',
    );

    expect(result, 'rood woko');
    verify(
      () => mockApi.post<dynamic>(
        ApiEndpoints.guidanceAsr,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).called(1);
  });
}

