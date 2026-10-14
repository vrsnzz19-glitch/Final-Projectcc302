import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daymate/main.dart';

void main() {
  testWidgets('DayMate app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const DayMateApp());

    expect(find.byType(DayMateApp), findsOneWidget);
  });

  testWidgets('wide screens use a phone-width layout and show tap banners', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DayMateApp());

    expect(tester.getSize(find.byType(Scaffold)).width, 480);

    await tester.tap(find.text('Habits').last);
    await tester.pump();

    expect(find.text('Switched to Daily Habits.'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();

    expect(tester.getSize(find.byType(Scaffold)).width, 390);
  });
}
