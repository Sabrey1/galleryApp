import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/widgets/video_badge.dart';

void main() {
  testWidgets('shows a play icon and formatted duration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: VideoBadge(durationSeconds: 125)),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('2:05'), findsOneWidget);
  });
}
