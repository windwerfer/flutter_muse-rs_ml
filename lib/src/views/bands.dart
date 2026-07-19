import 'package:flutter/material.dart';

/// Bands view (placeholder for phase 1): will later show frequency-band
/// power derived from the EEG stream.
class BandsView extends StatelessWidget {
  const BandsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Bands view\n(EEG band-power will be shown here)'),
    );
  }
}
