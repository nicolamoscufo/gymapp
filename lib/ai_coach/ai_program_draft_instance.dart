import 'ai_action_protocol.dart';

/// UI/persistence identity for one concrete AI program draft card.
///
/// It is intentionally separate from the semantic proposal content: two
/// different conversations may legitimately produce the same program, while
/// the same persisted card must never be committed twice.
class InstancedAiProgramActionProposal extends AiProgramActionProposal {
  static const payloadKey = 'draft_instance_id';

  final String draftInstanceId;

  const InstancedAiProgramActionProposal({
    required this.draftInstanceId,
    required super.kind,
    required super.summary,
    required super.rationale,
    super.evidence = const [],
    super.confidence = 'low',
    required super.schedules,
  });

  factory InstancedAiProgramActionProposal.fromProposal(
    AiProgramActionProposal proposal,
    String draftInstanceId,
  ) {
    return InstancedAiProgramActionProposal(
      draftInstanceId: draftInstanceId,
      kind: proposal.kind,
      summary: proposal.summary,
      rationale: proposal.rationale,
      evidence: proposal.evidence,
      confidence: proposal.confidence,
      schedules: proposal.schedules,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    payloadKey: draftInstanceId,
  };

  @override
  InstancedAiProgramActionProposal copyWith({
    AiProgramActionKind? kind,
    String? summary,
    String? rationale,
    List<String>? evidence,
    String? confidence,
    List<AiProgramScheduleDraft>? schedules,
  }) {
    return InstancedAiProgramActionProposal(
      draftInstanceId: draftInstanceId,
      kind: kind ?? this.kind,
      summary: summary ?? this.summary,
      rationale: rationale ?? this.rationale,
      evidence: evidence ?? this.evidence,
      confidence: confidence ?? this.confidence,
      schedules: schedules ?? this.schedules,
    );
  }
}

AiProgramActionProposal restoreProgramDraftInstance(
  AiProgramActionProposal proposal,
  Map<String, dynamic> payload,
) {
  final instanceId = payload[InstancedAiProgramActionProposal.payloadKey]
          ?.toString()
          .trim() ??
      '';
  if (instanceId.isEmpty) return proposal;
  return InstancedAiProgramActionProposal.fromProposal(proposal, instanceId);
}
