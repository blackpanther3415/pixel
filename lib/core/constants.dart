import 'package:flutter/material.dart';

class TabSpec {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final IconData selectedIcon;

  const TabSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.selectedIcon,
  });
}

const pixelTabs = <TabSpec>[
  TabSpec(
    id: 'gb',
    label: 'G.B',
    description: 'Security Gateway',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield,
  ),
  TabSpec(
    id: 'csb',
    label: 'CS.B',
    description: 'Structure Builder',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
  ),
  TabSpec(
    id: 'lb',
    label: 'L.B',
    description: 'Live Brain',
    icon: Icons.psychology_outlined,
    selectedIcon: Icons.psychology,
  ),
  TabSpec(
    id: 'cb',
    label: 'C.B',
    description: 'Clone Builder',
    icon: Icons.copy_all_outlined,
    selectedIcon: Icons.copy_all,
  ),
  TabSpec(
    id: 'bpb',
    label: 'B/P.B',
    description: 'Build & Plan',
    icon: Icons.flutter_dash_outlined,
    selectedIcon: Icons.flutter_dash,
  ),
  TabSpec(
    id: 'tb',
    label: 'T.B',
    description: 'Test Box',
    icon: Icons.science_outlined,
    selectedIcon: Icons.science,
  ),
  TabSpec(
    id: 'db',
    label: 'D.B',
    description: 'Data Bank',
    icon: Icons.storage_outlined,
    selectedIcon: Icons.storage,
  ),
  TabSpec(
    id: 'fb',
    label: 'F.B',
    description: 'Feature Bank',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
  ),
  TabSpec(
    id: 'llm',
    label: 'LLM',
    description: 'LLM Lab',
    icon: Icons.memory_outlined,
    selectedIcon: Icons.memory,
  ),
  TabSpec(
    id: 'mib',
    label: 'MI.B',
    description: 'Main Interface',
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
  ),
];

const appName = 'PIXEL';
const appVersion = '1.0.0';