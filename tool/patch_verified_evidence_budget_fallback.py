from pathlib import Path

path = Path('lib/ai_coach/ai_coach_context_budget.dart')
text = path.read_text()

old = """    context.remove('exercise_catalog');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    // Last-resort clipping keeps the payload valid JSON. This protects the
"""
new = """    context.remove('exercise_catalog');
    encoded = jsonEncode(context);
    if (encoded.length <= charBudget) return encoded;

    // Derived training facts are more valuable than duplicated raw logs when
    // the prompt is under severe pressure. Preserve the verified evidence
    // contract before falling back to generic clipping.
    final verified = context['verified_evidence'];
    if (verified is Map) {
      final evidenceOnly = <String, dynamic>{
        'verified_evidence': _compactVerifiedEvidence(verified),
      };
      encoded = jsonEncode(evidenceOnly);
      if (encoded.length <= charBudget) return encoded;

      final compact = Map<String, dynamic>.from(
        evidenceOnly['verified_evidence'] as Map,
      );
      for (final family in const [
        'strength',
        'volume_frequency',
        'progression',
        'readiness',
      ]) {
        compact.remove(family);
        encoded = jsonEncode({'verified_evidence': compact});
        if (encoded.length <= charBudget) return encoded;
      }

      final minimumEnvelope = <String, dynamic>{
        'source': compact['source'],
        'contract': compact['contract'],
        'coverage': compact['coverage'],
      }..removeWhere((_, value) => value == null);
      encoded = jsonEncode({'verified_evidence': minimumEnvelope});
      if (encoded.length <= charBudget) return encoded;

      for (final stringLimit in const [256, 128, 64, 32]) {
        final clippedEvidence = _clipValue(
          {'verified_evidence': minimumEnvelope},
          stringLimit: stringLimit,
          listLimit: 3,
          mapLimit: 16,
          depth: 0,
        );
        encoded = jsonEncode(clippedEvidence);
        if (encoded.length <= charBudget) return encoded;
      }
    }

    // Last-resort clipping keeps the payload valid JSON. This protects the
"""

if text.count(old) != 1:
    raise RuntimeError(
        f'evidence budget fallback anchor: expected 1, found {text.count(old)}'
    )

path.write_text(text.replace(old, new, 1))
