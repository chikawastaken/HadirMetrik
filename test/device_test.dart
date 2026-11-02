import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DeviceIdentity.clearCacheForTests());

  test('reuses a stored device id', () async {
    SharedPreferences.setMockInitialValues({'hadirmetrik.device_id.v1': 'flutter-stored'});

    expect(await DeviceIdentity.get(), 'flutter-stored');
    expect(await DeviceIdentity.get(), 'flutter-stored');
  });

  test('generates and persists a device id once', () async {
    SharedPreferences.setMockInitialValues({});

    final first = await DeviceIdentity.get();
    expect(first, startsWith('flutter-'));
    expect(first.length, greaterThan('flutter-'.length));

    DeviceIdentity.clearCacheForTests();
    expect(await DeviceIdentity.get(), first);
  });
}
