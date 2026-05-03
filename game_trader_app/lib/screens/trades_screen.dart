import 'package:flutter/material.dart';

import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/placeholder_panel.dart';
import 'shared_bottom_nav.dart';

class TradesScreen extends StatelessWidget {
  const TradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CasinoScaffold(
      appBar: CasinoTopNav(title: 'Activity'),
      bottomNavigationBar: SharedBottomNav(currentIndex: 1),
      body: PlaceholderPanel(
        icon: Icons.auto_graph,
        title: 'Activity',
        subtitle: 'No rounds yet.',
      ),
    );
  }
}
