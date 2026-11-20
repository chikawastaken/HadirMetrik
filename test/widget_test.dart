import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
import 'package:hadirmetrik/main.dart';
import 'package:hadirmetrik/screens/auth.dart';
import 'package:hadirmetrik/session.dart';
import 'package:http/http.dart' as http;

import 'support/memory_session_store.dart';

void main() {
  tearDown(() {
    Api.client = http.Client();
    Api.token = null;
    Session.store = SecureSessionStore();
  });

  testWidgets('app starts on the splash screen', (tester) async {
    Session.store = MemorySessionStore();
    await tester.pumpWidget(const HadirMetrik());
    expect(find.text('HadirMetrik'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an expired stored session is cleared and asks for login', (tester) async {
    final store = MemorySessionStore()
      ..value = StoredSession(
        token: 'expired',
        user: const {'role': 'employee'},
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
    Session.store = store;

    await tester.pumpWidget(const HadirMetrik());
    await tester.pumpAndSettle();

    expect(await store.read(), isNull);
    expect(Api.token, isNull);
    expect(find.byType(Login), findsNothing);
  });
}
