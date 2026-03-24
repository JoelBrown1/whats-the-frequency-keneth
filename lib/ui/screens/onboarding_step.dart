// lib/ui/screens/onboarding_step.dart
// Enum for the linear onboarding flow steps.

enum OnboardingStep {
  welcome,
  hardware,
  device,
  mains,
  level,
  calibration;

  static OnboardingStep fromIndex(int i) {
    if (i < 0 || i >= OnboardingStep.values.length) {
      return OnboardingStep.welcome;
    }
    return OnboardingStep.values[i];
  }
}
