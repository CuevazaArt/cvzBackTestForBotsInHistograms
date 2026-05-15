import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Modal that surfaces every field-level Pydantic validation issue plus a
/// contextual hint the API doesn't provide directly.
class ValidationErrorDialog extends StatelessWidget {
  final ApiValidationError error;
  final VoidCallback? onRetry;

  const ValidationErrorDialog({
    super.key,
    required this.error,
    this.onRetry,
  });

  static Future<void> show(BuildContext context, ApiValidationError error,
      {VoidCallback? onRetry}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ValidationErrorDialog(error: error, onRetry: onRetry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
      title: const Text('Please fix the following fields'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final issue in error.issues) ...[
                _IssueRow(issue: issue, hint: error.hintFor(issue)),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
        if (onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            child: const Text('Fix and retry'),
          ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  final ValidationIssue issue;
  final String hint;
  const _IssueRow({required this.issue, required this.hint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.25),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (issue.field.isNotEmpty)
            Text(
              issue.field,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.error,
                fontFamily: 'monospace',
              ),
            ),
          Text(issue.message),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
