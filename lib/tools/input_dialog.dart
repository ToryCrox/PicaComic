import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/components.dart';

/// 输入弹框的dialog
class InputDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String content;
  final TextPredicate predicate;
  final TextInputType keyboardType;
  final bool showPaste;

  const InputDialog._({
    Key? key,
    required this.title,
    required this.hint,
    required this.content,
    required this.predicate,
    required this.keyboardType,
    required this.showPaste,
  }) : super(key: key);

  @override
  State<InputDialog> createState() => _InputDialogState();

  static Future<String?> show({
    required BuildContext context,
    String title = '',
    String hint = '',
    String content = '',
    TextInputType keyboardType = TextInputType.text,
    TextPredicate? predicate,
    bool showPaste = false,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return InputDialog._(
          title: title,
          hint: hint,
          content: content,
          predicate: predicate ?? (text) => true,
          keyboardType: keyboardType,
          showPaste: showPaste,
        );
      },
    );
    return result;
  }
}

class _InputDialogState extends State<InputDialog> {
  final _controller = TextEditingController();

  late VoidCallback _onComplete;
  bool _isEditingEnable = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final result = widget.predicate(_controller.text);
      if (result != _isEditingEnable) {
        setState(() {
          _isEditingEnable = result;
        });
      }
    });
    _controller.text = widget.content;
    _onComplete = () {
      final text = _controller.text.trim();
      final result = widget.predicate(text);
      if (result) {
        Navigator.of(context).pop(text);
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) {
          _onComplete();
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          helperStyle: const TextStyle(
            //color: context.color.textTertiary,
            fontSize: 10,
          ),
          border: const OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      actions: [
        if (widget.showPaste)
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text ?? '';
              final result = widget.predicate(text);
              if (result) {
                _controller.text = text;
              } else {
                showToast(message: '粘贴内容不符合要求');
              }
            },
            child: const Text('粘贴'),
          ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _isEditingEnable ? _onComplete : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

typedef TextPredicate = bool Function(String text);
