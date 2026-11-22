import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playtier/data/repositories/playback_repository.dart';
import 'package:playtier/data/services/playback/playback_service.dart';
import 'package:playtier/domain/models/playback_exception.dart';
import 'package:playtier/domain/models/result.dart';

class MockPlaybackService extends Mock implements PlaybackService {}

void main() {
  late MockPlaybackService service;
  late PlaybackRepository repository;

  setUp(() {
    service = MockPlaybackService();
    repository = PlaybackRepository(service);
  });

  test('playList plays the context from the given index', () async {
    when(() => service.playContext(any(), startIndex: any(named: 'startIndex')))
        .thenAnswer((_) async {});

    final result =
        await repository.playList('spotify:playlist:p1', startIndex: 2);

    expect(result, isA<Ok<void>>());
    verify(() => service.playContext('spotify:playlist:p1', startIndex: 2))
        .called(1);
  });

  test('errors become Result.error instead of exceptions', () async {
    when(() => service.playContext(any(), startIndex: any(named: 'startIndex')))
        .thenThrow(const PlaybackException(PlaybackErrorKind.noDevice));

    final result = await repository.playList('spotify:playlist:p1');

    expect(result, isA<Error<void>>());
    final error = (result as Error<void>).error as PlaybackException;
    expect(error.kind, PlaybackErrorKind.noDevice);
  });

  test('simple commands also return Result.error', () async {
    when(service.pause)
        .thenThrow(const PlaybackException(PlaybackErrorKind.rejected));
    expect(await repository.pause(), isA<Error<void>>());
  });
}