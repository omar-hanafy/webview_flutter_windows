import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'loads a page before and after disposing the last webview',
    _loadPagesWithSeparateControllers,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _loadPagesWithSeparateControllers(WidgetTester tester) async {
  await _loadPage(tester, 'First page');
  // Native reconfiguration succeeds only after the last webview is gone.
  await WebviewController.initializeEnvironment();
  await _loadPage(tester, 'Second page');
}

Future<void> _loadPage(WidgetTester tester, String title) async {
  final controller = WebviewController();
  try {
    await controller.initialize();
    await tester.pumpWidget(Webview(controller));
    final loaded = controller.loadingState.firstWhere(
      (state) => state == LoadingState.navigationCompleted,
    );
    await controller.loadStringContent('<title>$title</title>');
    await loaded.timeout(const Duration(seconds: 30));
    expect(await controller.executeScript('document.title'), title);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  }
}
