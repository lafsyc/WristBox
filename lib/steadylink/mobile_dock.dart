import 'dart:ui';

import 'package:flutter/material.dart';

/// Clipped blur keeps the floating surface small and lets the list show through.
class MobileDock extends StatelessWidget {
  const MobileDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.connected,
    required this.connecting,
    required this.onInstallPressed,
    this.deviceName,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool connected, connecting;
  final VoidCallback onInstallPressed;
  final String? deviceName;

  static double contentInset(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final height = 64.0 + (scale.clamp(1.0, 2.0) - 1) * 12;
    return height +
        8 +
        MediaQuery.viewPaddingOf(context).bottom.clamp(12.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 300);
    final ink = dark ? const Color(0xFFF7F7FA) : const Color(0xFF22232B);
    final muted = dark ? const Color(0xFFBFC0CA) : const Color(0xFF60616E);
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final height = 64.0 + (scale.clamp(1.0, 2.0) - 1) * 12;
    final status = connected
        ? '已连接'
        : connecting
        ? '连接中'
        : '未连接';
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            children: [
              Expanded(
                child: _GlassCapsule(
                  dark: dark,
                  child: SizedBox(
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedAlign(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              alignment: Alignment(
                                -1.0 + selectedIndex * 2 / 3,
                                0,
                              ),
                              child: FractionallySizedBox(
                                widthFactor: 1 / 4,
                                heightFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(48),
                                    color: dark
                                        ? Colors.white.withValues(alpha: .14)
                                        : Colors.white.withValues(alpha: .85),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: dark ? .08 : .8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < 4; i++)
                                Expanded(
                                  child: Semantics(
                                    selected: selectedIndex == i,
                                    button: true,
                                    label: const ['设备', '商店', '应用', '我的'][i],
                                    child: ExcludeSemantics(
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          key: ValueKey('mobile-tab-$i'),
                                          borderRadius: BorderRadius.circular(
                                            48,
                                          ),
                                          onTap: () => onSelected(i),
                                          child: SizedBox.expand(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                AnimatedScale(
                                                  scale: selectedIndex == i
                                                      ? 1.06
                                                      : 1,
                                                  duration: duration,
                                                  child: Icon(
                                                    (selectedIndex == i
                                                        ? const [
                                                            Icons.watch_rounded,
                                                            Icons
                                                                .storefront_rounded,
                                                            Icons
                                                                .widgets_rounded,
                                                            Icons
                                                                .person_rounded,
                                                          ]
                                                        : const [
                                                            Icons
                                                                .watch_outlined,
                                                            Icons
                                                                .storefront_outlined,
                                                            Icons
                                                                .widgets_outlined,
                                                            Icons
                                                                .person_outline_rounded,
                                                          ])[i],
                                                    size: 22,
                                                    color: selectedIndex == i
                                                        ? ink
                                                        : muted,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Flexible(
                                                  child: Text(
                                                    const [
                                                      '设备',
                                                      '商店',
                                                      '应用',
                                                      '我的',
                                                    ][i],
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: selectedIndex == i
                                                          ? ink
                                                          : muted,
                                                      fontWeight:
                                                          selectedIndex == i
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: deviceName == null ? '选择安装包' : '安装到 $deviceName',
                child: Semantics(
                  label: '${deviceName ?? '设备'}，$status，选择安装包',
                  button: true,
                  child: ExcludeSemantics(
                    child: _GlassCapsule(
                      dark: dark,
                      child: SizedBox(
                        width: height,
                        height: height,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const ValueKey('mobile-quick-install'),
                            onTap: onInstallPressed,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 25,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 27,
                                          color: ink,
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child:
                                            connecting && !connected && !reduced
                                            ? SizedBox(
                                                width: 7,
                                                height: 7,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 1.5,
                                                      color: ink,
                                                    ),
                                              )
                                            : Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: connected
                                                      ? const Color(0xFF4DB78B)
                                                      : connecting
                                                      ? const Color(0xFFB49AEF)
                                                      : muted,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCapsule extends StatelessWidget {
  const _GlassCapsule({required this.dark, required this.child});
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(60),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? .24 : .09),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(60),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(60),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      const Color(0xFF464751).withValues(alpha: .78),
                      const Color(0xFF282931).withValues(alpha: .76),
                    ]
                  : [
                      const Color(0xFFF5F5FA).withValues(alpha: .8),
                      const Color(0xFFE3E3ED).withValues(alpha: .72),
                    ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .13 : .75),
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}
