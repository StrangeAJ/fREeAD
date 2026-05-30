import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/main.dart';

void main() {
  testWidgets('App initialization test', (WidgetTester tester) async {
    await tester.pumpWidget(const FreeAdApp());
    expect(find.text('FreeAd'), findsOneWidget);
  });
}
