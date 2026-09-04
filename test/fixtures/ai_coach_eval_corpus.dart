import 'package:gymapp/ai_coach/ai_coach_context_router.dart';

class AiCoachEvalCase {
  final String id;
  final String query;
  final AiCoachChatIntent intent;
  final bool programMutation;
  final Set<String> tags;

  const AiCoachEvalCase({
    required this.id,
    required this.query,
    required this.intent,
    this.programMutation = false,
    this.tags = const {},
  });
}

const aiCoachEvalCorpus = <AiCoachEvalCase>[
  AiCoachEvalCase(id: 'tech-01', query: 'Come faccio bene la panca piana?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-02', query: 'Mi controlli la tecnica dello squat?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-03', query: 'Il setup della panca va bene così?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-04', query: 'Dove metto la presa nel rematore?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-05', query: 'Come devo tenere i piedi nello stacco?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-06', query: 'La mia esecuzione della military press è corretta?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-07', query: 'Questo range of motion nello squat è sufficiente?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-08', query: 'Mi dai un form check per la panca?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-09', query: 'Come faccio questo esercizio senza perdere assetto?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-10', query: 'Ho il bilanciere troppo avanti nello squat?', intent: AiCoachChatIntent.technique),
  AiCoachEvalCase(id: 'tech-11', query: 'Guarda la foto: la posizione dei gomiti in panca è corretta?', intent: AiCoachChatIntent.technique, tags: {'image'}),
  AiCoachEvalCase(id: 'tech-12', query: 'La stance nello squat è troppo larga?', intent: AiCoachChatIntent.technique),

  AiCoachEvalCase(id: 'prog-01', query: 'Posso aumentare il peso in panca la prossima volta?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-02', query: 'Aumento i kg nello squat o tengo lo stesso carico?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-03', query: 'Sono fermo a 80 kg da tre settimane, che faccio?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-04', query: 'Sto stallando sulla military press.', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-05', query: 'Ho chiuso tutto a RPE 8: incremento?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-06', query: 'Se finisco con RIR 3 posso salire?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-07', query: 'Conviene fare un deload questa settimana?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-08', query: 'Prossima seduta aumento di 2.5 kg?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-09', query: 'Meglio aggiungere una rep oppure aumentare il peso?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-10', query: 'Sono in plateau con lo squat da un mese.', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-11', query: 'Come funziona la double progression per me?', intent: AiCoachChatIntent.progression),
  AiCoachEvalCase(id: 'prog-12', query: 'Il carico è salito ma le reps sono scese: continuo?', intent: AiCoachChatIntent.progression),

  AiCoachEvalCase(id: 'recovery-01', query: 'Sono stanco oggi, ha senso allenarmi pesante?', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-02', query: 'Ho dormito 5 ore stanotte.', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-03', query: 'Ho DOMS forti ai quadricipiti.', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-04', query: 'Mi fa male il ginocchio quando faccio squat.', intent: AiCoachChatIntent.recovery, tags: {'medical'}),
  AiCoachEvalCase(id: 'recovery-05', query: 'Sento fastidio alla spalla in panca.', intent: AiCoachChatIntent.recovery, tags: {'medical'}),
  AiCoachEvalCase(id: 'recovery-06', query: 'Quanto recupero mi serve dopo la seduta di ieri?', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-07', query: 'La readiness oggi è 4 su 10.', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-08', query: 'Posso allenarmi dopo una notte in bianco?', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-09', query: 'Le gambe sono distrutte dopo il workout.', intent: AiCoachChatIntent.recovery),
  AiCoachEvalCase(id: 'recovery-10', query: 'Sento un dolore acuto al gomito.', intent: AiCoachChatIntent.recovery, tags: {'medical'}),
  AiCoachEvalCase(id: 'recovery-11', query: 'Mi gira la testa dopo le serie pesanti.', intent: AiCoachChatIntent.recovery, tags: {'medical'}),
  AiCoachEvalCase(id: 'recovery-12', query: 'Sono molto affaticato questa settimana.', intent: AiCoachChatIntent.recovery),

  AiCoachEvalCase(id: 'progress-01', query: 'Sto migliorando in panca?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-02', query: 'Fammi vedere i progressi dell ultimo mese.', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-03', query: 'Come sta andando il mio volume rispetto a prima?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-04', query: 'Qual è il mio trend nelle ultime settimane?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-05', query: 'Ho fatto PR in qualche esercizio di recente?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-06', query: 'Come è cambiato il mio e1RM in panca?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-07', query: 'Confronta questo mese con il precedente.', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-08', query: 'Nelle ultime settimane sto andando meglio?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-09', query: 'La foto progressi mostra differenze rispetto alla precedente?', intent: AiCoachChatIntent.progress, tags: {'image'}),
  AiCoachEvalCase(id: 'progress-10', query: 'Sono più forte rispetto a un mese fa?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-11', query: 'Come si è mosso il volume nel tempo?', intent: AiCoachChatIntent.progress),
  AiCoachEvalCase(id: 'progress-12', query: 'Quale esercizio è migliorato di più?', intent: AiCoachChatIntent.progress),

  AiCoachEvalCase(id: 'program-discuss-01', query: 'Cosa ne pensi della mia scheda?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-02', query: 'La mia split push pull è bilanciata?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-03', query: 'Quanti giorni a settimana dovrei allenarmi?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-04', query: 'Il mio programma ha troppo volume settimanale?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-05', query: 'Meglio upper lower o full body per me?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-06', query: 'Perché nel mio mesociclo ci sono 4 settimane?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-07', query: 'Spiegami la routine attuale.', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-08', query: 'Genera un report sul mio programma.', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-09', query: 'Fammi capire se la scheda è bilanciata.', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-10', query: 'Posso cambiare esercizio nella mia scheda?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-11', query: 'Se volessi modificare il programma, cosa cambieresti?', intent: AiCoachChatIntent.program),
  AiCoachEvalCase(id: 'program-discuss-12', query: 'La nuova scheda mi sembra lunga.', intent: AiCoachChatIntent.program),

  AiCoachEvalCase(id: 'program-action-01', query: 'Creami una nuova scheda upper lower di 4 giorni.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-02', query: 'Modifica la mia scheda e sostituisci lo squat con leg press.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-03', query: 'Cambia il programma: togli un esercizio per le gambe.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-04', query: 'Aggiorna la routine per allenarmi tre giorni.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-05', query: 'Fammi una scheda per ipertrofia su quattro giorni.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-06', query: 'Genera un nuovo programma full body.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-07', query: 'Rifai la mia split su tre giorni.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-08', query: 'Sostituisci la panca con manubri nella scheda.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-09', query: 'Aggiungi un giorno alla mia scheda.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-10', query: 'Togli la leg press dal programma.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-11', query: 'Sposta lo stacco nella giornata pull della scheda.', intent: AiCoachChatIntent.program, programMutation: true),
  AiCoachEvalCase(id: 'program-action-12', query: 'Riduci da 4 a 3 giorni la mia routine.', intent: AiCoachChatIntent.program, programMutation: true),

  AiCoachEvalCase(id: 'general-01', query: 'Quante proteine servono di solito?', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-02', query: 'Quanto dovrebbe durare un allenamento?', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-03', query: 'Che differenza c è tra forza e ipertrofia?', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-04', query: 'Ciao coach.', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-05', query: 'Cosa devo fare oggi?', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-06', query: 'Come posso essere più costante?', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-07', query: 'Mi dai un consiglio?', intent: AiCoachChatIntent.general),
  AiCoachEvalCase(id: 'general-08', query: 'Spiegami la differenza tra serie e ripetizioni.', intent: AiCoachChatIntent.general),
];
