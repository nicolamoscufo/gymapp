from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'{label}: anchor not found in {path}')
    file.write_text(text.replace(old, new, 1))


# Home — schedule cards: neutral list surfaces, no promotional gradients.
replace_once(
    'lib/screens/home.dart',
    '''                        child: Container(
                          decoration: BoxDecoration(
                            gradient: schedule.isArchived
                                ? null
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accent.withValues(
                                        alpha: isDark ? 0.18 : 0.10,
                                      ),
                                      colorScheme.surface.withValues(
                                        alpha: 0.0,
                                      ),
                                    ],
                                  ),
                          ),''',
    '''                        child: Container(
                          decoration: BoxDecoration(
                            color: schedule.isArchived
                                ? Colors.transparent
                                : colorScheme.surfaceContainerLow,
                          ),''',
    'home schedule card gradient',
)

# Home — progress comparison card.
replace_once(
    'lib/screens/home.dart',
    '''      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.tertiary.withValues(alpha: isDark ? 0.20 : 0.12),
              Colors.transparent,
            ],
          ),
        ),''',
    '''      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
        ),''',
    'home exercise progress gradient',
)

# Home — history session cards.
replace_once(
    'lib/screens/home.dart',
    '''            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: isDark ? 0.18 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),''',
    '''            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
              ),''',
    'home history card gradient',
)

# Stats — data is the visual hierarchy; cards stay neutral.
replace_once(
    'lib/screens/stats.dart',
    '''    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
              Colors.transparent,
            ],
          ),
        ),''',
    '''    final colorScheme = theme.colorScheme;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
        ),''',
    'stats metric gradient',
)

# Session summary — compact, shareable neutral surface.
replace_once(
    'lib/screens/session_summary.dart',
    '''    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? 0.20 : 0.12),
            colorScheme.surface,
            colorScheme.tertiary.withValues(alpha: isDark ? 0.12 : 0.08),
          ],
        ),
      ),''',
    '''    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),''',
    'session summary gradient',
)

# Schedule detail — exercises are list items, not hero cards.
replace_once(
    'lib/screens/schedule_detail.dart',
    '''                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: isDark ? 0.18 : 0.10),
                            Colors.transparent,
                          ],
                        ),
                      ),''',
    '''                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                      ),''',
    'schedule detail exercise gradient',
)

# This test validates guided progression, not calendar-driven deload. Disable
# deload on its fixture so it remains deterministic in every calendar week.
replace_once(
    'test/home_undo_test.dart',
    '''      week: 1,
      createdAt: DateTime(2026),
      exercises: [''',
    '''      week: 1,
      createdAt: DateTime(2026),
      deloadEveryWeeks: 0,
      exercises: [''',
    'guided progression date fixture',
)

print('final UI cleanup applied')
