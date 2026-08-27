import 'package:flutter/material.dart';

import '../ai_coach/ai_coach_model_manager.dart';

class AiModelManagementScreen extends StatefulWidget {
  final AiCoachModelInstaller installer;

  const AiModelManagementScreen({
    super.key,
    this.installer = const FlutterGemmaAiCoachModelInstaller(),
  });

  @override
  State<AiModelManagementScreen> createState() =>
      _AiModelManagementScreenState();
}

class _AiModelManagementScreenState extends State<AiModelManagementScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _installed = false;
  int? _progress;
  String? _message;
  AiModelPreflightReport _preflight = AiModelPreflightReport.unknown();
  AiModelHealthReport _health = AiModelHealthReport.notInstalled();

  @override
  void initState() {
    super.initState();
    _refresh(runRecovery: true);
  }

  Future<void> _refresh({bool runRecovery = false}) async {
    setState(() => _loading = true);
    try {
      await widget.installer.initialize();
      AiModelRecoveryReport recovery = const AiModelRecoveryReport();
      if (runRecovery) {
        recovery = await widget.installer.recoverInterruptedState();
      }
      final preflight = await widget.installer.preflight();
      final installed = await widget.installer.isInstalled();
      final health = installed
          ? await widget.installer.verifyInstallation()
          : AiModelHealthReport.notInstalled();
      if (!mounted) return;
      setState(() {
        _preflight = preflight;
        _installed = installed;
        _health = health;
        _loading = false;
        if (recovery.userMessage != null) _message = recovery.userMessage;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Impossibile verificare il modello locale: $error';
      });
    }
  }

  Future<bool> _confirmWarnings() async {
    if (!_preflight.needsConfirmation) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Compatibilità non ideale'),
            content: Text(
              '${_preflight.warnings.join('\n\n')}\n\nPuoi continuare, ma il modello potrebbe essere più lento o Android potrebbe chiudere l’app sotto pressione di memoria.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continua'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _install({bool reinstall = false}) async {
    if (_busy || !_preflight.canInstall) return;
    if (!await _confirmWarnings()) return;

    if (reinstall) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Reinstalla modello?'),
              content: const Text(
                'Il modello corrente verrà eliminato e scaricato nuovamente. Le chat, le schede e lo storico non verranno toccati.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Reinstalla'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _message = reinstall
          ? 'Reinstallazione di ${widget.installer.modelName}…'
          : 'Download di ${widget.installer.modelName}…';
    });

    try {
      final onProgress = (int progress) {
        if (!mounted) return;
        setState(() => _progress = progress.clamp(0, 100));
      };
      if (reinstall) {
        await widget.installer.reinstall(onProgress: onProgress);
      } else {
        await widget.installer.install(onProgress: onProgress);
      }
      if (!mounted) return;
      setState(() => _message = 'Modello installato e verificato.');
      await _refresh();
    } on AiModelInstallException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.retryable
            ? '${error.message}\nPuoi riprovare: gli errori di rete temporanei vengono ritentati automaticamente.'
            : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Installazione fallita: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Verifica del runtime LiteRT-LM…';
    });
    try {
      final health = await widget.installer.verifyInstallation();
      if (!mounted) return;
      setState(() {
        _health = health;
        _message = health.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Rimuovi modello locale?'),
            content: Text(
              'Verranno liberati circa ${widget.installer.modelSizeLabel}. Chat, allenamenti, schede e dati personali resteranno sul dispositivo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Rimuovi'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _message = 'Rimozione del modello…';
    });
    try {
      await widget.installer.uninstall();
      if (!mounted) return;
      setState(() => _message = 'Modello rimosso.');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Rimozione fallita: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Modello AI locale')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ModelIdentityCard(installer: widget.installer),
                const SizedBox(height: 12),
                _DeviceCompatibilityCard(preflight: _preflight),
                const SizedBox(height: 12),
                _HealthCard(installed: _installed, health: _health),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(_message!),
                  ),
                ],
                if (_busy && _progress != null) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress! / 100),
                  const SizedBox(height: 6),
                  Text(
                    '$_progress%',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge,
                  ),
                ],
                const SizedBox(height: 16),
                if (!_installed)
                  FilledButton.icon(
                    key: const ValueKey('ai-model-download'),
                    onPressed: _busy || !_preflight.canInstall
                        ? null
                        : () => _install(),
                    icon: const Icon(Icons.download),
                    label: Text('Scarica ${widget.installer.modelName}'),
                  )
                else ...[
                  FilledButton.icon(
                    key: const ValueKey('ai-model-verify'),
                    onPressed: _busy ? null : _verify,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verifica installazione'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('ai-model-reinstall'),
                    onPressed: _busy || !_preflight.canInstall
                        ? null
                        : () => _install(reinstall: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reinstalla modello'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const ValueKey('ai-model-remove'),
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Rimuovi modello dal dispositivo'),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Nota sul resume: flutter_gemma supporta il resume quando il server HTTP lo consente. Il CDN Hugging Face può richiedere di ricominciare il trasferimento dopo un’interruzione; l’app conserva comunque lo stato, ripulisce i file orfani e permette un retry sicuro.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _ModelIdentityCard extends StatelessWidget {
  final AiCoachModelInstaller installer;

  const _ModelIdentityCard({required this.installer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              installer.modelName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text('${installer.modelSizeLabel} • on-device • privacy-first'),
            const SizedBox(height: 10),
            Text('Versione: ${installer.modelVersion}'),
            if (installer.expectedSha256.isNotEmpty)
              Text(
                'SHA-256 artifact: ${installer.expectedSha256.substring(0, 16)}…',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCompatibilityCard extends StatelessWidget {
  final AiModelPreflightReport preflight;

  const _DeviceCompatibilityCard({required this.preflight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = preflight.device;
    final status = switch (preflight.suitability) {
      AiModelSuitability.suitable => 'Compatibile',
      AiModelSuitability.warning => 'Compatibile con avvisi',
      AiModelSuitability.unsupported => 'Non compatibile',
      AiModelSuitability.unknown => 'Compatibilità non verificata',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compatibilità dispositivo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            if (device.manufacturer.isNotEmpty || device.model.isNotEmpty)
              Text('${device.manufacturer} ${device.model}'.trim()),
            if (device.totalMemoryBytes != null)
              Text('RAM fisica: ${_gb(device.totalMemoryBytes!)} GB'),
            if (device.availableStorageBytes != null)
              Text('Spazio libero: ${_gb(device.availableStorageBytes!)} GB'),
            if (device.abis.isNotEmpty) Text('ABI: ${device.abis.join(', ')}'),
            if (device.androidSdk != null)
              Text('Android API: ${device.androidSdk}'),
            if (preflight.blockers.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...preflight.blockers.map(
                (item) => _EvidenceLine(
                  icon: Icons.block,
                  text: item,
                  isError: true,
                ),
              ),
            ],
            if (preflight.warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...preflight.warnings.map(
                (item) => _EvidenceLine(
                  icon: Icons.warning_amber_rounded,
                  text: item,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final bool installed;
  final AiModelHealthReport health;

  const _HealthCard({required this.installed, required this.health});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (health.status) {
      AiModelHealthStatus.notInstalled => 'Non installato',
      AiModelHealthStatus.healthy => 'Verificato',
      AiModelHealthStatus.legacyUnverified => 'Legacy / non verificato',
      AiModelHealthStatus.versionMismatch => 'Versione diversa',
      AiModelHealthStatus.runtimeBroken => 'Runtime non valido',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(installed ? Icons.health_and_safety : Icons.cloud_off),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stato installazione',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Chip(label: Text(label)),
              ],
            ),
            Text(health.message),
            if (installed && health.runtimeLoadVerified) ...[
              const SizedBox(height: 8),
              const _EvidenceLine(
                icon: Icons.check_circle_outline,
                text: 'Test di caricamento LiteRT-LM superato.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isError;

  const _EvidenceLine({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: isError ? colors.error : colors.tertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
