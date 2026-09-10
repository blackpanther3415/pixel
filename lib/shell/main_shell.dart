import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/settings_dialog.dart';
import '../tabs/bpb/build_plan_tab.dart';
import '../tabs/cb/clone_tab.dart';
import '../tabs/csb/structure_tab.dart';
import '../tabs/db/data_bank_tab.dart';
import '../tabs/fb/feature_bank_tab.dart';
import '../tabs/gb/security_tab.dart';
import '../tabs/lb/live_brain_tab.dart';
import '../tabs/llm/llm_lab_tab.dart';
import '../tabs/mib/main_interface_tab.dart';
import '../tabs/tb/test_box_tab.dart';

class MainShell extends StatefulWidget {
  final AppState appState;
  const MainShell({super.key, required this.appState});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 9; // land on MI.B (main interface)
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      SecurityTab(state: widget.appState),
      StructureTab(state: widget.appState),
      LiveBrainTab(state: widget.appState),
      CloneTab(state: widget.appState),
      BuildPlanTab(state: widget.appState),
      TestBoxTab(state: widget.appState),
      DataBankTab(state: widget.appState),
      FeatureBankTab(state: widget.appState),
      LlmLabTab(state: widget.appState),
      MainInterfaceTab(state: widget.appState),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tab = pixelTabs[_index];
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final navigation = wide
              ? _NavigationRail(index: _index, onSelect: _select)
              : _BottomBar(index: _index, onSelect: _select);
          return Row(
            children: [
              navigation,
              Expanded(
                child: Column(
                  children: [
                    if (wide)
                      _TopHeader(
                          tab: tab, state: widget.appState),
                    Expanded(
                      child: IndexedStack(index: _index, children: _tabs),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _select(int i) => setState(() => _index = i);
}

class _TopHeader extends StatelessWidget {
  final TabSpec tab;
  final AppState state;
  const _TopHeader({required this.tab, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(tab.selectedIcon, size: 18, color: AppColors.primaryLight),
          const SizedBox(width: 8),
          Text(
            '${tab.label}  ·  ${tab.description}',
            style: const TextStyle(
                color: AppColors.textHigh,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                size: 18, color: AppColors.textMid),
            tooltip: 'Settings — providers, security level, routing',
            onPressed: () =>
                SettingsDialog.show(context, state),
          ),
          const Text('PIXEL', style: _logo),
        ],
      ),
    );
  }

  static const TextStyle _logo = TextStyle(
    color: AppColors.primaryLight,
    fontSize: 16,
    fontWeight: FontWeight.w900,
    letterSpacing: 3,
  );
}

class _NavigationRail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _NavigationRail({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      color: AppColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border),
          Expanded(
            child: ListView.builder(
              itemCount: pixelTabs.length,
              itemBuilder: (context, i) {
                final t = pixelTabs[i];
                final selected = i == index;
                return Tooltip(
                  message: '${t.label} — ${t.description}',
                  child: _NavItem(
                    icon: selected ? t.selectedIcon : t.icon,
                    selected: selected,
                    onTap: () => onSelect(i),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('v0.1', style: TextStyle(color: AppColors.textLow, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Icon(icon,
                color: selected ? AppColors.primaryLight : AppColors.textMid,
                size: 22),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _BottomBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (int i = 0; i < pixelTabs.length; i++)
                _NavItem(
                  icon: i == index ? pixelTabs[i].selectedIcon : pixelTabs[i].icon,
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}