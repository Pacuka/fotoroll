import 'package:flutter/material.dart';

import '../i18n.dart';

/// FutureBuilder with a spinner and a retryable error state.
class Loader<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  const Loader({super.key, required this.future, required this.builder, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${t('error')}: ${snap.error}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: Text(t('linux_retry'))),
            ]),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return builder(snap.data as T);
      },
    );
  }
}
