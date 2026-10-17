import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';

void main() {
  test('versions compare by major, then minor, then patch', () {
    expect(const ServerVersion(3, 3, 3).isAtLeast(Since.tagRename), isTrue);
    expect(const ServerVersion(3, 2, 9).isAtLeast(Since.tagRename), isFalse);
    expect(const ServerVersion(4, 0, 0).isAtLeast(Since.tagRename), isTrue);
    expect(const ServerVersion(3, 1, 0).isAtLeast(Since.supported), isTrue);
    expect(const ServerVersion(2, 9, 9).isAtLeast(Since.supported), isFalse);
    expect(const ServerVersion(3, 2), const ServerVersion(3, 2, 0));
    expect(ServerVersion.fromJson({'major': 3, 'minor': 3, 'patch': 3}).toString(), 'v3.3.3');
    expect(Since.rotateApiKey.short, 'v3.2');
  });

  test('an unknown server version hides nothing', () {
    final api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:9', apiKey: 'k'));
    expect(api.supports(Since.tagRename), isTrue);
    api.serverVersion.value = const ServerVersion(3, 2, 1);
    expect(api.supports(Since.rotateApiKey), isTrue);
    expect(api.supports(Since.tagRename), isFalse);
  });
}
