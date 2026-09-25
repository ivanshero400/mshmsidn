// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mshmsidn/main.dart';

void main() {
  testWidgets('App starts with setup page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ar');

    await tester.runAsync(() async {
      await tester.pumpWidget(const AuraAdhanApp());
      // Give time for async initialization (SharedPreferences loading)
      await Future.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // The first screen should be the setup/location page.
    expect(find.text('مرحباً بك في أذان'), findsOneWidget);
    expect(find.text('تحديد موقعي تلقائياً'), findsOneWidget);
    expect(find.text('البحث عن مدينتي يدوياً'), findsOneWidget);
  });
}
