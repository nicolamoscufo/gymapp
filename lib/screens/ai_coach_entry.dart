import 'package:flutter/material.dart';

import '../app_data_store.dart';
import 'ai_coach.dart';

class AiCoachEntryScreen extends StatefulWidget {
  const AiCoachEntryScreen({super.key});

  @override
  State<AiCoachEntryScreen> createState() => _AiCoachEntryScreenState();
}

class _AiCoachEntryScreenState extends State<AiCoachEntryScreen> {
  late final Future<AppDataBundle> _bundleFuture = AppDataStore.loadBundle();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDataBundle>(
      future: _bundleFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('AI Coach')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossibile caricare i dati di allenamento: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final bundle = snapshot.data;
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return AiCoachScreen(
          history: bundle.history,
          schedules: bundle.schedules,
          bodyLogs: bundle.bodyLogs,
        );
      },
    );
  }
}
