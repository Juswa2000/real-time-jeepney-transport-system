// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:jeepjeep/main.dart';

void main() {
  testWidgets('App starts on role selection', (WidgetTester tester) async {
    await tester.pumpWidget(const JeepJeepApp());
    expect(find.text('Select your role'), findsOneWidget);
    expect(find.text('Commuter'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });
}
