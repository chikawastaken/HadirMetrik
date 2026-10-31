import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
import 'package:hadirmetrik/deeplink.dart';
import 'package:hadirmetrik/screens/auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    Api.token = null;
    Api.client = http.Client();
    DeepLink.pendingToken = null;
  });

  testWidgets(
    'change password blocks a new password shorter than 8 characters',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChangePassword()));

      await tester.tap(find.text('Simpan Kata Sandi'));
      await tester.pump();

      expect(find.text('Kata sandi baru minimal 8 karakter'), findsOneWidget);
    },
  );

  testWidgets(
    'invitation accept reserves the token and opens face enrollment',
    (tester) async {
      Api.token = 'session-token';
      DeepLink.remember('abc123abc123abc1');
      Api.client = MockClient((request) async {
        expect(request.url.path, '/api/v1/invitations/abc123abc123abc1/accept');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'next_step': 'face_enrollment'},
          }),
          200,
        );
      });

      await tester.pumpWidget(const MaterialApp(home: InvitationAccept()));
      await tester.pumpAndSettle();

      expect(find.text('Registrasi Wajah'), findsOneWidget);
      expect(DeepLink.hasPending, isFalse);
    },
  );

  testWidgets(
    'invitation owned by another account offers a switch to the employee login',
    (tester) async {
      Api.token = 'hr-session';
      DeepLink.remember('abc123abc123abc1');
      Api.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'Undangan ini bukan milik akun Anda.',
            'errors': {
              'code': ['INVITATION_NOT_OWNED'],
            },
          }),
          403,
        );
      });

      await tester.pumpWidget(const MaterialApp(home: InvitationAccept()));
      await tester.pumpAndSettle();

      expect(find.text('Undangan ini bukan milik akun Anda.'), findsOneWidget);

      await tester.tap(find.text('Masuk dengan akun karyawan'));
      await tester.pumpAndSettle();

      expect(Api.token, isNull);
      expect(DeepLink.pendingToken, 'abc123abc123abc1');
      expect(find.text('Selamat Datang'), findsOneWidget);
    },
  );
}
