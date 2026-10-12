import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/core/utils/semver.dart';

void main() {
  group('SemVer.tryParse (strict regex)', () {
    test('accepts plain semver', () {
      final v = SemVer.tryParse('1.2.3');
      expect(v, isNotNull);
      expect(v!.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.toString(), '1.2.3');
    });

    test('trims surrounding whitespace', () {
      expect(SemVer.tryParse(' 1.2.3 ')?.toString(), '1.2.3');
    });

    test('rejects "latest"', () {
      expect(SemVer.tryParse('latest'), isNull);
    });

    test('rejects prereleases', () {
      expect(SemVer.tryParse('1.2.3-rc1'), isNull);
      expect(SemVer.tryParse('1.2.3-beta.1'), isNull);
      expect(SemVer.tryParse('1.2.3-alpha'), isNull);
    });

    test('rejects build metadata in the version string', () {
      // Build numbers live in pubspec (1.1.0+2); strict parse of the full
      // string must fail — the '+' part is never compared by the engine.
      expect(SemVer.tryParse('1.1.0+2'), isNull);
    });

    test('rejects malformed input', () {
      expect(SemVer.tryParse(''), isNull);
      expect(SemVer.tryParse('1'), isNull);
      expect(SemVer.tryParse('1.2'), isNull);
      expect(SemVer.tryParse('1.2.3.4'), isNull);
      expect(SemVer.tryParse('a.b.c'), isNull);
      expect(SemVer.tryParse('1.x.3'), isNull);
      // Strict: the tag prefix is NOT accepted here — use tryParseTag.
      expect(SemVer.tryParse('v1.2.3'), isNull);
    });
  });

  group('SemVer.tryParseTag (v-prefix stripping)', () {
    test('strips leading v', () {
      final v = SemVer.tryParseTag('v1.1.0');
      expect(v, isNotNull);
      expect(v!.toString(), '1.1.0');
      expect(v.major, 1);
      expect(v.minor, 1);
      expect(v.patch, 0);
    });

    test('accepts tag without v prefix', () {
      expect(SemVer.tryParseTag('1.1.0')!.toString(), '1.1.0');
    });

    test('rejects non-semver tags', () {
      expect(SemVer.tryParseTag('latest'), isNull);
      expect(SemVer.tryParseTag('v'), isNull);
      expect(SemVer.tryParseTag('v1.2'), isNull);
      expect(SemVer.tryParseTag('release-1'), isNull);
      expect(SemVer.tryParseTag(''), isNull);
    });
  });

  group('SemVer.compareTo (major → minor → patch)', () {
    test('equal versions compare 0', () {
      expect(SemVer.tryParse('1.1.0')!.compareTo(SemVer.tryParse('1.1.0')!), 0);
    });

    test('major dominates minor and patch', () {
      expect(
        SemVer.tryParse('2.0.0')!.compareTo(SemVer.tryParse('1.9.9')!),
        greaterThan(0),
      );
      expect(
        SemVer.tryParse('1.0.0')!.compareTo(SemVer.tryParse('2.0.0')!),
        lessThan(0),
      );
    });

    test('minor dominates patch', () {
      expect(
        SemVer.tryParse('1.2.0')!.compareTo(SemVer.tryParse('1.1.9')!),
        greaterThan(0),
      );
      expect(
        SemVer.tryParse('1.1.9')!.compareTo(SemVer.tryParse('1.2.0')!),
        lessThan(0),
      );
    });

    test('patch decides when major/minor equal', () {
      expect(
        SemVer.tryParse('1.1.1')!.compareTo(SemVer.tryParse('1.1.0')!),
        greaterThan(0),
      );
      expect(
        SemVer.tryParse('1.1.0')!.compareTo(SemVer.tryParse('1.1.1')!),
        lessThan(0),
      );
    });
  });
}
