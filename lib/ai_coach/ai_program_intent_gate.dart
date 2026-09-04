class AiProgramIntentGate {
  const AiProgramIntentGate();

  bool isMutationRequest(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty || !_programTerms.hasMatch(normalized)) {
      return false;
    }

    if (_nonMutationPatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return false;
    }

    if (_createPatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return true;
    }

    return _mutationVerbs.hasMatch(normalized);
  }

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static final RegExp _programTerms = RegExp(
    r'\b(?:scheda|programma|routine|split|workout plan|training plan)\b',
    caseSensitive: false,
  );

  static final List<RegExp> _nonMutationPatterns = [
    RegExp(r'\bcosa ne pensi\b'),
    RegExp(r'\bspiegami\b'),
    RegExp(r'\bfammi capire\b'),
    RegExp(r'\bgenera(?:mi)? un report\b'),
    RegExp(r'\breport (?:sul|sulla|del|della)\b'),
    RegExp(r'\bse volessi\b'),
    RegExp(r'\bposso\b'),
    RegExp(r'\bpotrei\b'),
    RegExp(r'\bdovrei\b'),
    RegExp(r'\bconviene\b'),
    RegExp(r'\bmi sembra\b'),
    RegExp(r'\bcome sta\b'),
    RegExp(r'\bperch[eé]\b'),
    RegExp(r'\bquanti?\b'),
    RegExp(r'\bmeglio\b'),
  ];

  static final List<RegExp> _createPatterns = [
    RegExp(
      r'\b(?:crea|creami|fammi|genera|generami|costruisci)\b.{0,48}\b(?:scheda|programma|routine|split)\b',
    ),
    RegExp(
      r'\b(?:create|make|build|generate)\b.{0,48}\b(?:workout plan|training plan|program|routine|split)\b',
    ),
  ];

  static final RegExp _mutationVerbs = RegExp(
    r'\b(?:modifica|cambia|sostituisci|aggiorna|rifai|aggiungi|togli|rimuovi|sposta|riduci|aumenta|elimina|modify|change|replace|update|rebuild|add|remove|move|reduce)\b',
    caseSensitive: false,
  );
}
