import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/services/auth/auth_service.dart';

void main() {
  group(
    'GoogleSignInFailure.truncateDetail (Phase 2: bounded diagnostics)',
    () {
      test('detail longer than bound is truncated with ellipsis suffix', () {
        final long = List.filled(500, 'x').join();
        final result = GoogleSignInFailure.truncateDetail(long);
        expect(result, isNotNull);
        expect(
          result!.length,
          GoogleSignInFailure.maxDetailLength + '...'.length,
        );
        expect(result.endsWith('...'), true);
        expect(result.startsWith(List.filled(200, 'x').join()), true);
      });

      test('short detail is unchanged', () {
        const short = 'Google sign-in canceled (canceled).';
        expect(GoogleSignInFailure.truncateDetail(short), short);
      });

      test('detail exactly at bound is unchanged (no ellipsis)', () {
        final exact = List.filled(
          GoogleSignInFailure.maxDetailLength,
          'y',
        ).join();
        final result = GoogleSignInFailure.truncateDetail(exact);
        expect(result, exact);
        expect(result!.endsWith('...'), false);
      });

      test('null detail stays null', () {
        expect(GoogleSignInFailure.truncateDetail(null), isNull);
      });

      test('empty and whitespace-only detail normalize to null', () {
        expect(GoogleSignInFailure.truncateDetail(''), isNull);
        expect(GoogleSignInFailure.truncateDetail('   '), isNull);
      });

      test('bound constant is 200', () {
        expect(GoogleSignInFailure.maxDetailLength, 200);
      });

      test(
        'typed failure keeps the truncated detail for the Show details toggle',
        () {
          final long = List.filled(500, 'z').join();
          final failure = GoogleSignInFailure(
            code: 'supabase_rejected',
            detail: GoogleSignInFailure.truncateDetail(long),
            hint: 'hint',
          );
          expect(
            failure.detail!.length,
            GoogleSignInFailure.maxDetailLength + '...'.length,
          );
          expect(failure.detail!.endsWith('...'), true);
        },
      );
    },
  );
}
