// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:xiaoche_app_v1/connection_model.dart';
import 'package:xiaoche_app_v1/main.dart';
import 'package:xiaoche_app_v1/settings_model.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsModel()),
          ChangeNotifierProxyProvider<SettingsModel, ConnectionModel>(
            create: (_) => ConnectionModel(),
            update: (_, settings, connection) =>
                (connection ?? ConnectionModel())..applySettings(settings),
          ),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);
  });
}
