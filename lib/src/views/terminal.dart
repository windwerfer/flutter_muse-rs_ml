import 'package:flutter/material.dart';

/// Terminal view (placeholder for phase 1): will later show the raw event /
/// control log streamed from the headset.
class TerminalView extends StatelessWidget {
  const TerminalView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Terminal view\n(device control/event log will be shown here)'),
    );
  }
}
