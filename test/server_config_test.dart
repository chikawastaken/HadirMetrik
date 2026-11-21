import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/server_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfig.reset();
  });

  test('normalize trims slashes and adds the API prefix', () {
    expect(ServerConfig.normalize('http://192.168.1.10:8000/'), 'http://192.168.1.10:8000/api/v1');
    expect(ServerConfig.normalize('192.168.1.10:8000'), 'http://192.168.1.10:8000/api/v1');
    expect(ServerConfig.normalize('http://host:8000/api/v1/'), 'http://host:8000/api/v1');
    expect(ServerConfig.normalize('https://example.test'), 'https://example.test/api/v1');
  });

  test('save persists a URL and reset returns to the platform default', () async {
    await ServerConfig.save('192.168.18.124:8000');
    expect(ServerConfig.baseUrl, 'http://192.168.18.124:8000/api/v1');

    await ServerConfig.reset();
    expect(ServerConfig.baseUrl, 'http://127.0.0.1:8000/api/v1');
  });

  test('load restores a previously saved URL', () async {
    SharedPreferences.setMockInitialValues({'debug.api_base_url': 'http://10.1.2.3:9000/api/v1'});
    await ServerConfig.load();
    expect(ServerConfig.baseUrl, 'http://10.1.2.3:9000/api/v1');
  });
}
