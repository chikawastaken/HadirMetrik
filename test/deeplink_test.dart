import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/deeplink.dart';

void main() {
  group('InvitationLink.tokenFrom', () {
    test('accepts hadirmetrik://invitations/<token>', () {
      expect(
        InvitationLink.tokenFrom(Uri.parse('hadirmetrik://invitations/ckK1gU8JdApnINgUfvCKfd9It9p7kSFl')),
        'ckK1gU8JdApnINgUfvCKfd9It9p7kSFl',
      );
    });

    test('accepts the host-less form with the token as the last segment', () {
      expect(
        InvitationLink.tokenFrom(Uri.parse('hadirmetrik:///invitations/abc123DEF456ghi789')),
        'abc123DEF456ghi789',
      );
    });

    test('rejects other schemes, hosts, and malformed tokens', () {
      expect(InvitationLink.tokenFrom(Uri.parse('https://invitations/abc123DEF456')), isNull);
      expect(InvitationLink.tokenFrom(Uri.parse('hadirmetrik://other/abc123DEF456')), isNull);
      expect(InvitationLink.tokenFrom(Uri.parse('hadirmetrik://invitations/short')), isNull);
      expect(InvitationLink.tokenFrom(Uri.parse('hadirmetrik://invitations/abc-123')), isNull);
      expect(InvitationLink.tokenFrom(Uri.parse('hadirmetrik://invitations/a/b')), isNull);
    });
  });
}
