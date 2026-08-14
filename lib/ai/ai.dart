import 'ai_client.dart';
import 'ai_settings_store.dart';
import 'ai_translation_service.dart';

export 'ai_models.dart';
export 'ai_translation_service.dart';

final aiSettings = AiSettingsStore();
final aiClient = AiClient();
final aiTranslationService = AiTranslationService(
  settings: aiSettings,
  client: aiClient,
);
