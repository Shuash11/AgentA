/// Pure, total release-notes changelog parser (cycle-29 P2, Adviser ruling 2).
///
/// UI-layer logic against the already-contracted `notes` string
/// (`contracts/update-engine.yaml` v1.1.1 — unchanged; the engine keeps
/// passing the raw GitHub release body and `publishedAt`).
///
/// Lenient by design (a release body is human-authored markdown; GitHub's
/// auto-generated bodies use arbitrary category titles — keepachangelog.com
/// 1.1.0 / docs.github.com "Automatically generated release notes"):
///  - recognizes markdown H3 section headings `### New` / `### Improved` /
///    `### Fixed` case-insensitively, tolerating 0-3 leading spaces
///    (CommonMark ATX), an omitted space (`###New`), trailing colons and
///    surrounding whitespace;
///  - any other H3 heading becomes a GENERIC section — its heading and items
///    are never dropped;
///  - bullets `-` / `*` / `+` and numbered `1.` / `1)` items under a heading;
///    non-bullet prose inside a section is kept as an item (nothing dropped);
///  - content before the first H3 heading is kept as the model's preamble;
///  - a body with NO H3 structure at all falls back to [RawReleaseNotes]
///    (the renderer shows the cycle-26 inset-well text dump);
///  - horizontal rules / setext underlines (`---`, `===`, `***`) are skipped;
///  - inline markdown (`**bold**`, links) is kept verbatim — no markdown
///    package, pure Dart string parsing;
///  - never throws: null, empty, or garbage input always yields a model.
///
/// Totality note: the parser never throws and never returns null; the
/// RENDERER decides presentation (item truncation, empty-section hiding).
library;

/// How a section heading was recognized — the renderer maps this to the
/// section icon (neumorphism spec §5 second channel; icons are never
/// color-only).
enum NotesSectionKind { added, improved, fixed, generic }

/// One changelog section: a heading plus its bullet items, in body order.
final class ReleaseNotesSection {
  /// Display heading. Recognized kinds get the canonical label
  /// (New / Improved / Fixed); generic sections keep the body's own heading
  /// (trailing colon stripped).
  final String heading;

  final NotesSectionKind kind;

  /// Items in body order, markers stripped, trimmed. Kept mutable so the
  /// single-pass builder can append; the parser is still pure (fresh model
  /// per call, nothing shared).
  final List<String> items;

  ReleaseNotesSection({
    required this.heading,
    required this.kind,
    List<String>? items,
  }) : items = items ?? <String>[];
}

/// Parsed release notes — the sealed result of [parseReleaseNotes].
sealed class ReleaseNotes {
  const ReleaseNotes();
}

/// Structured changelog: optional preamble + sections in body order.
final class ParsedReleaseNotes extends ReleaseNotes {
  /// Prose found before the first H3 heading (null when none). Preserved so
  /// an intro sentence is never dropped.
  final String? preamble;

  final List<ReleaseNotesSection> sections;

  const ParsedReleaseNotes({this.preamble, required this.sections});
}

/// Unstructured body — no H3 structure. The renderer shows [text] verbatim
/// in the inset well (identical to the pre-cycle-29 treatment).
final class RawReleaseNotes extends ReleaseNotes {
  /// The raw text, trimmed.
  final String text;

  const RawReleaseNotes(this.text);
}

/// H3 ATX heading: 0-3 leading spaces, exactly `###` (not `####`+ via the
/// lookahead), optional space, heading text, optional trailing whitespace.
final RegExp _headingPattern = RegExp(r'^\s{0,3}###(?!#)\s*(.*?)\s*$');

/// Bullet item: `-` / `*` / `+` or numbered `1.` / `1)`, a space, then the
/// item text. Leading whitespace is tolerated (nested bullets flatten).
final RegExp _bulletPattern = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+(.+?)\s*$');

/// Horizontal rules and setext underlines — decorative separators, skipped.
final RegExp _rulePattern = RegExp(r'^\s*[-=*_]{3,}\s*$');

/// Parses the raw release body into a [ReleaseNotes] model. TOTAL: never
/// throws on any input (null / empty / garbage included); see the library
/// doc for the full lenient-parsing contract.
ReleaseNotes parseReleaseNotes(String? raw) {
  final text = (raw ?? '').replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return const RawReleaseNotes('');

  final preamble = <String>[];
  final sections = <ReleaseNotesSection>[];
  ReleaseNotesSection? current;

  for (final line in text.split('\n')) {
    final headingMatch = _headingPattern.firstMatch(line);
    if (headingMatch != null) {
      final heading = headingMatch.group(1) ?? '';
      // A bare `###` (or colon-only heading) carries nothing renderable —
      // skip the line rather than inventing an empty section.
      if (heading.trim().isEmpty || heading.trim() == ':') continue;
      current = _startSection(heading);
      sections.add(current);
      continue;
    }

    final bulletMatch = _bulletPattern.firstMatch(line);
    if (bulletMatch != null) {
      final item = (bulletMatch.group(1) ?? '').trim();
      if (current != null) {
        current.items.add(item);
      } else {
        // A bullet before any heading still belongs to the preamble —
        // kept (marker stripped), never dropped.
        preamble.add(item);
      }
      continue;
    }

    final trimmed = line.trim();
    if (trimmed.isEmpty || _rulePattern.hasMatch(line)) continue;
    if (current != null) {
      // Prose inside a section (e.g. `**Full Changelog**` link line) is
      // kept as an item — nothing dropped.
      current.items.add(trimmed);
    } else {
      preamble.add(trimmed);
    }
  }

  // No H3 structure at all (the common auto-generated body) → the raw
  // fallback; the full trimmed text is preserved verbatim.
  if (sections.isEmpty) return RawReleaseNotes(text);

  return ParsedReleaseNotes(
    preamble: preamble.isEmpty ? null : preamble.join('\n'),
    sections: sections,
  );
}

/// Starts a section from a captured heading: recognized kinds get the
/// canonical display label; everything else is generic with the body's own
/// heading (one trailing colon + whitespace tolerated away).
ReleaseNotesSection _startSection(String rawHeading) {
  final label = rawHeading.trim();
  final normalized =
      (label.endsWith(':') ? label.substring(0, label.length - 1) : label)
          .trim();
  switch (normalized.toLowerCase()) {
    case 'new':
      return ReleaseNotesSection(heading: 'New', kind: NotesSectionKind.added);
    case 'improved':
      return ReleaseNotesSection(
        heading: 'Improved',
        kind: NotesSectionKind.improved,
      );
    case 'fixed':
      return ReleaseNotesSection(
        heading: 'Fixed',
        kind: NotesSectionKind.fixed,
      );
    default:
      return ReleaseNotesSection(
        heading: normalized.isEmpty ? label : normalized,
        kind: NotesSectionKind.generic,
      );
  }
}
