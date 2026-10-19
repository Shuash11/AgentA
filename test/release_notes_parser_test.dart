import 'package:flutter_test/flutter_test.dart';
import 'package:aiproject/presentation/shared/release_notes_parser.dart';

void main() {
  group('parseReleaseNotes — recognized headings (cycle-29 ruling 2)', () {
    test('### New / ### Improved / ### Fixed become canonical sections', () {
      final model = parseReleaseNotes(
        '### New\n'
        '- Chat search\n'
        '### Improved\n'
        '- Faster sync\n'
        '### Fixed\n'
        '- Crash on launch',
      );

      expect(model, isA<ParsedReleaseNotes>());
      final parsed = model as ParsedReleaseNotes;
      expect(parsed.preamble, isNull);
      expect(parsed.sections, hasLength(3));

      expect(parsed.sections[0].heading, 'New');
      expect(parsed.sections[0].kind, NotesSectionKind.added);
      expect(parsed.sections[0].items, ['Chat search']);

      expect(parsed.sections[1].heading, 'Improved');
      expect(parsed.sections[1].kind, NotesSectionKind.improved);
      expect(parsed.sections[1].items, ['Faster sync']);

      expect(parsed.sections[2].heading, 'Fixed');
      expect(parsed.sections[2].kind, NotesSectionKind.fixed);
      expect(parsed.sections[2].items, ['Crash on launch']);
    });

    test(
      'headings match case-insensitively with colon/whitespace tolerance',
      () {
        final model = parseReleaseNotes(
          '###  fixed: \n- a\n###IMPROVED\n- b\n###NEW\n- c',
        );

        expect(model, isA<ParsedReleaseNotes>());
        final parsed = model as ParsedReleaseNotes;
        expect(parsed.sections, hasLength(3));
        expect(parsed.sections[0].heading, 'Fixed');
        expect(parsed.sections[0].kind, NotesSectionKind.fixed);
        expect(parsed.sections[1].heading, 'Improved');
        expect(parsed.sections[1].kind, NotesSectionKind.improved);
        expect(parsed.sections[2].heading, 'New');
        expect(parsed.sections[2].kind, NotesSectionKind.added);
      },
    );

    test('bullet markers -, *, + and numbered 1. / 1) are all recognized', () {
      final model = parseReleaseNotes(
        '### New\n'
        '- dash item\n'
        '* star item\n'
        '+ plus item\n'
        '### Improved\n'
        '1. one dot\n'
        '2) two paren',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections[0].items, ['dash item', 'star item', 'plus item']);
      expect(parsed.sections[1].items, ['one dot', 'two paren']);
    });

    test('items are trimmed and empty lines between items are skipped', () {
      final model = parseReleaseNotes(
        '### New\n-   padded item   \n\n- tight item\n',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections.single.items, ['padded item', 'tight item']);
    });
  });

  group('parseReleaseNotes — unknown H3 sections (never dropped)', () {
    test('an unknown H3 renders as its own generic section with its items', () {
      final model = parseReleaseNotes(
        '### Performance\n- Startup 30% faster\n- Less memory',
      );

      expect(model, isA<ParsedReleaseNotes>());
      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections, hasLength(1));
      expect(parsed.sections.single.heading, 'Performance');
      expect(parsed.sections.single.kind, NotesSectionKind.generic);
      expect(parsed.sections.single.items, [
        'Startup 30% faster',
        'Less memory',
      ]);
    });

    test('a generic heading keeps its own label, trailing colon stripped', () {
      final model = parseReleaseNotes('### Security:\n- CVE fix');

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections.single.heading, 'Security');
      expect(parsed.sections.single.kind, NotesSectionKind.generic);
    });

    test('mixed recognized and generic sections keep body order', () {
      final model = parseReleaseNotes(
        '### New\n- a\n### Security\n- b\n### Fixed\n- c',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections.map((s) => s.heading).toList(), [
        'New',
        'Security',
        'Fixed',
      ]);
      expect(parsed.sections.map((s) => s.kind).toList(), [
        NotesSectionKind.added,
        NotesSectionKind.generic,
        NotesSectionKind.fixed,
      ]);
    });
  });

  group('parseReleaseNotes — raw fallback (no H3 structure)', () {
    test('no headings → raw with the exact trimmed text', () {
      const body = 'Bug fixes and improvements';
      final model = parseReleaseNotes(body);

      expect(model, isA<RawReleaseNotes>());
      expect((model as RawReleaseNotes).text, body);
    });

    test('H2-only body (GitHub auto-generated shape) → raw fallback', () {
      const body =
          "## What's Changed\n"
          '* feat: chat search by @dev\n'
          '**Full Changelog**: https://example.com/compare/v1.3.0...v1.4.0';
      final model = parseReleaseNotes(body);

      expect(model, isA<RawReleaseNotes>());
      expect((model as RawReleaseNotes).text, body);
    });

    test('null → raw empty (never throws)', () {
      final model = parseReleaseNotes(null);

      expect(model, isA<RawReleaseNotes>());
      expect((model as RawReleaseNotes).text, '');
    });

    test('empty and whitespace-only bodies → raw empty', () {
      for (final input in <String?>['', '   ', '\n\t \n']) {
        final model = parseReleaseNotes(input);
        expect(model, isA<RawReleaseNotes>(), reason: 'input: "$input"');
        expect((model as RawReleaseNotes).text, '', reason: 'input: "$input"');
      }
    });

    test('garbage input never crashes and degrades to raw', () {
      const body = '###\n\x00{{]][(( \n***\n:\n---';
      final model = parseReleaseNotes(body);

      // A bare `###` and a colon-only heading are skipped; the remaining
      // prose (`\x00{{]][((`) has no owning section and no H3 structure →
      // the raw fallback preserves everything verbatim.
      expect(model, isA<RawReleaseNotes>());
      expect((model as RawReleaseNotes).text, body.trim());
    });
  });

  group('parseReleaseNotes — lenient content rules (nothing dropped)', () {
    test('prose before the first heading is kept as the preamble', () {
      final model = parseReleaseNotes(
        'Thanks for using AgentA!\n'
        '### New\n'
        '- Chat search',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.preamble, 'Thanks for using AgentA!');
      expect(parsed.sections, hasLength(1));
    });

    test(
      'bullets before the first heading join the preamble (marker stripped)',
      () {
        final model = parseReleaseNotes('- early note\n### Fixed\n- a');

        final parsed = model as ParsedReleaseNotes;
        expect(parsed.preamble, 'early note');
        expect(parsed.sections.single.items, ['a']);
      },
    );

    test('multi-line preamble keeps its line breaks', () {
      final model = parseReleaseNotes('Line one\nLine two\n### New\n- a');

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.preamble, 'Line one\nLine two');
    });

    test('prose inside a section becomes an item (kept, not dropped)', () {
      final model = parseReleaseNotes(
        '### New\n- a\n**Full Changelog**: https://example.com',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections.single.items, [
        'a',
        '**Full Changelog**: https://example.com',
      ]);
    });

    test('horizontal rules and setext underlines are skipped', () {
      final model = parseReleaseNotes('### New\n- a\n---\n### Fixed\n- b\n===');

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections[0].items, ['a']);
      expect(parsed.sections[1].items, ['b']);
      expect(parsed.preamble, isNull);
    });

    test('H2/H4 heading lines are not sections (kept as content)', () {
      final model = parseReleaseNotes(
        '## Release title\n### New\n- a\n#### sub note',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.preamble, '## Release title');
      expect(parsed.sections, hasLength(1));
      expect(parsed.sections.single.heading, 'New');
      // The H4 line falls under the owning section as prose → item.
      expect(parsed.sections.single.items, ['a', '#### sub note']);
    });

    test('CRLF line endings parse identically to LF', () {
      final model = parseReleaseNotes('### New\r\n- a\r\n### Fixed\r\n- b');

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections, hasLength(2));
      expect(parsed.sections[0].items, ['a']);
      expect(parsed.sections[1].items, ['b']);
    });

    test(
      'a >5-item section keeps ALL items (truncation is the renderer job)',
      () {
        final model = parseReleaseNotes(
          '### New\n- 1\n- 2\n- 3\n- 4\n- 5\n- 6\n- 7',
        );

        final parsed = model as ParsedReleaseNotes;
        expect(parsed.sections.single.items, hasLength(7));
        expect(parsed.sections.single.items.last, '7');
      },
    );

    test('a heading-only section is kept with zero items', () {
      final model = parseReleaseNotes('### New\n### Fixed\n- a');

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections, hasLength(2));
      expect(parsed.sections[0].heading, 'New');
      expect(parsed.sections[0].items, isEmpty);
      expect(parsed.sections[1].items, ['a']);
    });

    test('inline markdown is kept verbatim (no markdown package)', () {
      final model = parseReleaseNotes(
        '### New\n- The **search** bar and `pin` chats',
      );

      final parsed = model as ParsedReleaseNotes;
      expect(parsed.sections.single.items, [
        'The **search** bar and `pin` chats',
      ]);
    });
  });

  group('parseReleaseNotes — totality (fuzz-ish sweep)', () {
    test('never throws on pathological inputs', () {
      const inputs = <String?>[
        null,
        '',
        ' ',
        '\n\n\n',
        '###',
        '###:',
        '####',
        '#',
        '##',
        '-',
        '*',
        '1.',
        '### New',
        '### New\n### New\n### New',
        '###New###',
        '-\n-\n-',
        '1) 2) 3)',
        '😀 ### New 🎉\n- 😀',
      ];
      for (final input in inputs) {
        expect(
          () => parseReleaseNotes(input),
          returnsNormally,
          reason: 'input: "$input"',
        );
        parseReleaseNotes(input); // and yields a usable model
      }
    });

    test('same input → equal model (pure, no shared mutable state)', () {
      const body = '### New\n- a';
      final first = parseReleaseNotes(body) as ParsedReleaseNotes;
      final second = parseReleaseNotes(body) as ParsedReleaseNotes;

      expect(second.sections.single.heading, first.sections.single.heading);
      expect(second.sections.single.kind, first.sections.single.kind);
      expect(second.sections.single.items, first.sections.single.items);
      // Mutating one model never affects the other.
      first.sections.single.items.add('b');
      expect(second.sections.single.items, ['a']);
    });
  });
}
