import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows an error dialog when webview creation fails', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('io.jns.webview.win'), (
          call,
        ) async {
          throw PlatformException(
            code: 'environment_creation_failed',
            message: 'WebView2 runtime is not installed',
          );
        });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Error'), findsOneWidget);
    expect(find.textContaining('environment_creation_failed'), findsOneWidget);
  });
}
