import 'package:car_logix/core/widgets/live_speech_ticker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App smoke test', () {
    expect(1 + 1, equals(2));
  });

  testWidgets('LiveSpeechTicker scrolls smoothly without overflow on very long speech', (tester) async {
    final longTranscript = List.generate(40, (i) => 'د ب ن ${1000 + i}').join(' ');

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: LiveSpeechTicker(
              isListening: true,
              transcript: '',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('شريط كتابة فوري متحرك'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: LiveSpeechTicker(
              isListening: true,
              transcript: longTranscript,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(longTranscript), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
