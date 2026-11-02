import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
import 'package:hadirmetrik/screens/auth.dart';
import 'package:hadirmetrik/screens/face.dart';
import 'package:hadirmetrik/state.dart';
import 'package:hadirmetrik/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _templates(List<Map<String, dynamic>> rows) => http.Response(
      jsonEncode({'success': true, 'data': rows}),
      200,
      headers: {'content-type': 'application/json'},
    );

Widget _host(Widget child) => MaterialApp(theme: buildTheme(), home: child);

void main() {
  setUp(() {
    app.faceTemplates = [];
    app.faceEnrollment = null;
    app.faceEnrollmentFailed = false;
    app.faceError = null;
    app.faceBusy = false;
  });

  tearDown(() {
    Api.client = http.Client();
  });

  testWidgets('empty state offers the enrollment action', (tester) async {
    Api.client = MockClient((request) async => _templates([]));

    await tester.pumpWidget(_host(const FaceEnrollmentScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada wajah terdaftar'), findsOneWidget);
    expect(find.text('Daftarkan Wajah'), findsOneWidget);
    expect(find.text('Verifikasi wajah belum aktif'), findsOneWidget);
  });

  testWidgets('pending template is shown as waiting, never verified', (tester) async {
    Api.client = MockClient((request) async => _templates([
          {'id': 8, 'version': 2, 'status': 'pending', 'provider': 'local_tflite'},
        ]));

    await tester.pumpWidget(_host(const FaceEnrollmentScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Menunggu verifikasi'), findsWidgets);
    expect(find.text('Wajah terverifikasi'), findsNothing);
    expect(find.text('Versi 2'), findsOneWidget);
    expect(find.text('Cabut'), findsOneWidget);
  });

  testWidgets('a failed upload is not reported as sent', (tester) async {
    app.faceEnrollment = null;
    app.faceEnrollmentFailed = true;
    app.faceError = 'Tidak bisa terhubung ke server.';

    await tester.pumpWidget(_host(const FaceSuccess()));
    await tester.pumpAndSettle();

    expect(find.text('Pendaftaran belum terkirim'), findsOneWidget);
    expect(find.text('Pendaftaran wajah dikirim'), findsNothing);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('profile card summarises the pending template', (tester) async {
    Api.client = MockClient((request) async => _templates([
          {'id': 8, 'version': 2, 'status': 'pending'},
        ]));

    await tester.pumpWidget(_host(const Scaffold(body: SingleChildScrollView(child: FaceDataCard()))));
    await tester.pumpAndSettle();

    expect(find.text('Template v2'), findsOneWidget);
    expect(find.text('Menunggu verifikasi model wajah'), findsOneWidget);
  });
}
