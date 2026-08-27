import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/schedule.dart';
import '../models/workout.dart';
import '../top_set_backoff.dart' as top_set_backoff;
import 'active_workout.dart';
import 'program_history.dart';
import 'schedule_detail.dart';

class CalendarScreen extends StatefulWidget {
  final List<Schedule> schedules;
  final List<WorkoutSession> history;
  final int defaultRestSeconds;
  final double defaultBackoffReductionPercent;
  final VoidCallback onRefresh;
  final VoidCallback onSaveSchedules;
  final bool showAppBar;

  const CalendarScreen({
    super.key,
    required this.schedules,
    required this.history,
    required this.defaultRestSeconds,
    this.defaultBackoffReductionPercent =
        top_set_backoff.defaultBackoffReductionPercent,
    required this.onRefresh,
    required this.onSaveSchedules,
    this.showAppBar = true,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _visibleCalendarMonth;
  late DateTime _selectedCalendarDay;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _visibleCalendarMonth = DateTime(today.year, today.month);
    _selectedCalendarDay = DateTime(today.year, today.month, today.day);
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Lun',
      DateTime.tuesday => 'Mar',
      DateTime.wednesday => 'Mer',
      DateTime.thursday => 'Gio',
      DateTime.friday => 'Ven',
      DateTime.saturday => 'Sab',
      DateTime.sunday => 'Dom',
      _ => '?',
    };
  }

  String _monthTitle(DateTime month) {
    const names = [
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }

  List<DateTime?> _calendarMonthCells(DateTime month) {
    final firstDay = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmptyCells = firstDay.weekday - 1;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leadingEmptyCells, null),
      ...List.generate(
        daysInMonth,
        (index) => DateTime(month.year, month.month, index + 1),
      ),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  void _showMonth(DateTime month) {
    final normalizedMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final selectedDay = math.min(_selectedCalendarDay.day, daysInMonth);
    setState(() {
      _visibleCalendarMonth = normalizedMonth;
      _selectedCalendarDay = DateTime(
        normalizedMonth.year,
        normalizedMonth.month,
        selectedDay,
      );
    });
  }

  List<Schedule> _schedulesForDate(DateTime date) {
    return widget.schedules
        .where((s) => !s.isArchived && s.isPlannedOn(date))
        .toList();
  }

  List<WorkoutSession> _sessionsForDate(DateTime date) {
    final normalized = _dateOnly(date);
    final sessions = widget.history
        .where((session) => _dateOnly(session.startTime) == normalized)
        .toList();
    sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
    return sessions;
  }

  int _completedSetCount(WorkoutSession session) {
    var count = 0;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        if (set.isCompleted && !set.isWarmup) {
          count++;
        }
      }
    }
    return count;
  }

  double _volumeForSession(WorkoutSession session) {
    var volume = 0.0;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        if (set.isCompleted && !set.isWarmup) {
          volume += set.weight * set.reps;
        }
      }
    }
    return volume;
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = math.max(1, duration.inMinutes);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) {
      return '$minutes min';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatWeight(double weight) {
    return weight % 1 == 0
        ? weight.toStringAsFixed(0)
        : weight.toStringAsFixed(1);
  }

  String _agendaDateLabel(DateTime date) {
    final today = _dateOnly(DateTime.now());
    final normalized = _dateOnly(date);
    if (normalized == today) {
      return 'Oggi';
    }
    if (normalized == today.add(const Duration(days: 1))) {
      return 'Domani';
    }
    return '${_weekdayLabel(date.weekday)} ${date.day}/${date.month}';
  }

  Future<void> _openScheduleDetail(Schedule schedule) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleDetailScreen(
          schedule: schedule,
          history: widget.history,
          defaultRestSeconds: widget.defaultRestSeconds,
          defaultBackoffReductionPercent: widget.defaultBackoffReductionPercent,
          onUpdate: () {
            widget.onSaveSchedules();
          },
        ),
      ),
    );
    widget.onRefresh();
  }

  Future<void> _openProgramHistory(Schedule schedule) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProgramHistoryScreen(
          schedule: schedule,
          history: widget.history,
        ),
      ),
    );
  }

  Future<void> _startSchedule(Schedule schedule) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ActiveWorkoutScreen(
          schedule: schedule,
          history: widget.history,
          defaultRestSeconds: widget.defaultRestSeconds,
          defaultBackoffReductionPercent: widget.defaultBackoffReductionPercent,
        ),
      ),
    );
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cells = _calendarMonthCells(_visibleCalendarMonth);
    final selectedSchedules = _schedulesForDate(_selectedCalendarDay);
    final selectedSessions = _sessionsForDate(_selectedCalendarDay);
    final today = _dateOnly(DateTime.now());

    final content = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _monthTitle(_visibleCalendarMonth),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mese precedente',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _showMonth(
                        DateTime(
                          _visibleCalendarMonth.year,
                          _visibleCalendarMonth.month - 1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mese successivo',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _showMonth(
                        DateTime(
                          _visibleCalendarMonth.year,
                          _visibleCalendarMonth.month + 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(7, (index) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          _weekdayLabel(index + 1),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cells.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final day = cells[index];
                    if (day == null) {
                      return const SizedBox.shrink();
                    }
                    final normalizedDay = _dateOnly(day);
                    final planned = _schedulesForDate(day);
                    final completed = _sessionsForDate(day);
                    final isSelected = normalizedDay == _selectedCalendarDay;
                    final isToday = normalizedDay == today;
                    final hasCompleted = completed.isNotEmpty;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _selectedCalendarDay = normalizedDay;
                      }),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : hasCompleted
                              ? colorScheme.tertiaryContainer
                              : planned.isNotEmpty
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isToday
                                ? colorScheme.tertiary
                                : colorScheme.outlineVariant,
                            width: isToday ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isSelected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (planned.isNotEmpty)
                              Text(
                                '${planned.length}',
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (hasCompleted)
                              Icon(
                                Icons.check_circle,
                                size: 11,
                                color: isSelected
                                    ? colorScheme.onPrimary
                                    : colorScheme.tertiary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '${_agendaDateLabel(_selectedCalendarDay)}: ${selectedSchedules.length} schede - ${selectedSessions.length} svolti',
                  style: theme.textTheme.labelLarge,
                ),
                if (selectedSchedules.isEmpty && selectedSessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Nessun allenamento programmato o completato nel giorno selezionato.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (selectedSchedules.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Schede programmate',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  ...selectedSchedules.map(
                    (schedule) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(schedule.title),
                      subtitle: Text(
                        'Week ${schedule.currentWeek(now: _selectedCalendarDay)}${schedule.isDeloadWeek(now: _selectedCalendarDay) ? ' - deload' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Evoluzione programma',
                            icon: const Icon(Icons.timeline),
                            onPressed: () => _openProgramHistory(schedule),
                          ),
                          FilledButton(
                            onPressed: () => _startSchedule(schedule),
                            child: const Text('Start'),
                          ),
                        ],
                      ),
                      onTap: () => _openScheduleDetail(schedule),
                    ),
                  ),
                ],
                if (selectedSessions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Allenamenti svolti',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  ...selectedSessions.map((session) {
                    final duration = session.endTime.difference(
                      session.startTime,
                    );
                    final setCount = _completedSetCount(session);
                    final volume = _volumeForSession(session);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.check_circle,
                        color: colorScheme.tertiary,
                      ),
                      title: Text(session.scheduleTitle),
                      subtitle: Text(
                        '${_formatTime(session.startTime)} - ${_formatDuration(duration)} - $setCount set - ${_formatWeight(volume)} kg',
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    if (!widget.showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
      body: content,
    );
  }
}
