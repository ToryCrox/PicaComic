import 'ai_client.dart';

/// 将半角方括号信息替换为不可变占位符，避免作者、社团等元信息被翻译。
class BracketTextProtection {
  final String protectedText;
  final List<String> _tokens;
  final Map<String, String> _originalTexts;

  const BracketTextProtection(
    this.protectedText,
    this._tokens,
    this._originalTexts,
  );

  factory BracketTextProtection.protect(String text) {
    var index = 0;
    final tokens = <String>[];
    final originalTexts = <String, String>{};
    final protectedText = text.replaceAllMapped(RegExp(r'\[[^\]\r\n]*\]'), (
      match,
    ) {
      final token = '⟪PICA_BRACKET_${index.toString().padLeft(4, '0')}⟫';
      tokens.add(token);
      originalTexts[token] = match.group(0)!;
      index++;
      return token;
    });
    return BracketTextProtection(protectedText, tokens, originalTexts);
  }

  String restore(String translated) {
    final found = RegExp(
      r'⟪PICA_BRACKET_\d{4}⟫',
    ).allMatches(translated).map((match) => match.group(0)!).toList();
    if (!_sameSequence(found, _tokens)) {
      throw const AiRequestException('AI 未能完整保留方括号中的不翻译内容，请重新翻译');
    }
    var result = translated;
    for (final token in _tokens) {
      result = result.replaceAll(token, _originalTexts[token]!);
    }
    return result;
  }

  static bool _sameSequence(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
