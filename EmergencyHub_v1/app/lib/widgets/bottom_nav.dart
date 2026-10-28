import 'package:flutter/material.dart';

import '../theme.dart';

class EhbrBottomNav extends StatelessWidget {
  const EhbrBottomNav({
    super.key,
    this.index = 0,
    this.onTap,
    this.activeColor = EhbrColors.brandLight,
  });

  final int index;
  final ValueChanged<int>? onTap;
  final Color activeColor;

  static const _items = <(IconData, String)>[
    (Icons.home_outlined, 'Home'),
    (Icons.map_outlined, 'Map'),
    (Icons.phone_outlined, 'Contacts'),
    (Icons.newspaper_outlined, 'News'),
    (Icons.account_circle_outlined, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(color: EhbrColors.ink, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onTap?.call(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_items[i].$1, size: 24, color: i == index ? activeColor : Colors.white),
                    const SizedBox(height: 1),
                    Text(_items[i].$2,
                        style: manrope(11, FontWeight.w400, i == index ? activeColor : Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
