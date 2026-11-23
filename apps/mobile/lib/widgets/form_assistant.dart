import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';

class FormAssistantButton extends StatelessWidget {
  const FormAssistantButton({
    super.key,
    required this.formType,
    required this.prompt,
    required this.onApply,
  });

  final String formType;
  final String prompt;
  final ValueChanged<Map<String, dynamic>> onApply;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _FormAssistantDialog(
              formType: formType,
              prompt: prompt,
              onApply: onApply,
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, color: appTeal),
          label: Text(appText('AI fill form')),
        ),
      );
}

class _FormAssistantDialog extends StatefulWidget {
  const _FormAssistantDialog({
    required this.formType,
    required this.prompt,
    required this.onApply,
  });

  final String formType;
  final String prompt;
  final ValueChanged<Map<String, dynamic>> onApply;

  @override
  State<_FormAssistantDialog> createState() => _FormAssistantDialogState();
}

class _FormAssistantDialogState extends State<_FormAssistantDialog> {
  final _descriptionController = TextEditingController();
  Map<String, dynamic>? _suggestions;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    if (_descriptionController.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _suggestions = null;
    });
    final result = await Api.assistForm(
      formType: widget.formType,
      message: _descriptionController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok && result.data?['suggestions'] is Map) {
        _suggestions = Map<String, dynamic>.from(result.data!['suggestions'] as Map);
      } else {
        _error = result.errorMessage ?? 'Could not prepare suggestions.';
      }
    });
  }

  String _displayValue(dynamic value) {
    if (value == null || value == '') return '—';
    if (value is List) {
      return value.map((item) {
        if (item is Map) {
          return '${appText(item['category']?.toString() ?? '')} × ${item['quantity']}';
        }
        return item.toString();
      }).join(', ');
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(appText(_suggestions == null
            ? 'AI fill form'
            : 'Review suggestions')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_suggestions == null) ...[
                  Text(appText(widget.prompt)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  Text(appText('AI suggestions are ready to review.')),
                  const SizedBox(height: 12),
                  ..._suggestions!.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${appText(entry.key)}: ${_displayValue(entry.value)}'),
                      )),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                if (_loading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: Text(appText('Cancel')),
          ),
          if (_suggestions == null)
            FilledButton(
              onPressed: _loading ? null : _suggest,
              child: Text(appText('Review suggestions')),
            )
          else
            FilledButton(
              onPressed: () {
                widget.onApply(_suggestions!);
                Navigator.of(context).pop();
              },
              child: Text(appText('Apply to form')),
            ),
        ],
      );
}
