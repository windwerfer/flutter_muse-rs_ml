import 'package:flutter/material.dart';

/// Raw EEG view (placeholder for phase 1): will later render live EEG traces
/// from the connected headset.
class RawEegView extends StatelessWidget {
  const RawEegView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Raw EEG view\n(live EEG traces will be shown here)'),
    );
  }
}
