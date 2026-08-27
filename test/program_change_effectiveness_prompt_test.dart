import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/local_ai_coach_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Coach prompt keeps program effectiveness associative, not causal', () {
    expect(systemCoachingPrompt, contains('program_change_effectiveness'));
    expect(systemCoachingPrompt, contains('never prove'));
    expect(systemCoachingPrompt, contains('insufficient data'));
  });
}
