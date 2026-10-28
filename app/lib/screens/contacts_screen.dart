import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../phone.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/async_body.dart';

class _Item {
  const _Item(this.name, this.number, this.subtitle, this.icon, this.group);
  final String name, number, subtitle, group;
  final IconData icon;
}

/// Numbers come from the admin console (Settings → Emergency contacts).
/// Search and Favorites (stars) are kept on the phone.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.reloadToken});
  final int reloadToken;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const _favKey = 'favorite_contacts';
  final _q = TextEditingController();
  Set<String> _favs = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _favs = (p.getStringList(_favKey) ?? []).toSet());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _toggle(String number) async {
    setState(() => _favs.contains(number) ? _favs.remove(number) : _favs.add(number));
    try {
      (await SharedPreferences.getInstance()).setStringList(_favKey, _favs.toList());
    } catch (_) {}
  }

  List<_Item> _items() {
    final cfg = Session.config;
    return [
      _Item('National Emergency Hotline', cfg.sosNumber, 'Same number the SOS button dials', Icons.notifications_none_rounded, 'National Emergency Contact'),
      if (cfg.hotline.isNotEmpty)
        _Item('Barangay hotline', cfg.hotline, cfg.locationLine.isEmpty ? 'Barangay office' : cfg.locationLine, Icons.account_balance_outlined, 'Local Emergency Contacts'),
      for (final c in cfg.contacts.where((c) => c.category == 'local'))
        _Item(c.name, c.number, 'Local emergency contact', Icons.local_phone_outlined, 'Local Emergency Contacts'),
      for (final c in cfg.contacts.where((c) => c.category == 'utility'))
        _Item(c.name, c.number, 'Utility / disaster desk', Icons.build_circle_outlined, 'Utility & Disaster Desk Contacts'),
    ];
  }

  Widget _row(_Item i) => _ContactRow(
        item: i,
        favorite: _favs.contains(i.number),
        onFavorite: () => _toggle(i.number),
        onOpen: () => showContactDetails(
          context,
          name: i.name,
          number: i.number,
          category: i.group,
          detail: i.subtitle,
          favorite: _favs.contains(i.number),
          onToggleFavorite: () => _toggle(i.number),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AsyncBody<bool>(
      load: () async {
        await Session.loadConfig();
        return true;
      },
      reloadToken: widget.reloadToken,
      builder: (context, _, refresh) {
        final all = _items();
        final term = _q.text.trim().toLowerCase();
        final shown = term.isEmpty
            ? all
            : all.where((i) => i.name.toLowerCase().contains(term) || i.number.contains(term) || i.subtitle.toLowerCase().contains(term)).toList();
        final favs = shown.where((i) => _favs.contains(i.number)).toList();
        final groups = <String>[];
        for (final i in shown) {
          if (!groups.contains(i.group)) groups.add(i.group);
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 110),
            children: [
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: term.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
                  filled: true,
                  fillColor: EhbrColors.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              if (favs.isNotEmpty) ...[
                const _Heading('Favorites'),
                for (final i in favs) _row(i),
                const SizedBox(height: 10),
              ],
              for (final g in groups) ...[
                _Heading(g),
                for (final i in shown.where((i) => i.group == g)) _row(i),
                const SizedBox(height: 10),
              ],
              if (shown.isEmpty)
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: term.isEmpty ? 'No local contacts yet' : 'No contacts found',
                  message: term.isEmpty
                      ? 'Your barangay will add police, fire, medical and utility numbers here.'
                      : 'Nothing matches “${_q.text.trim()}”. Try a different name or number.',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: manrope(14, FontWeight.w700, EhbrColors.ink)),
      );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.item, required this.favorite, required this.onFavorite, required this.onOpen});
  final _Item item;
  final bool favorite;
  final VoidCallback onFavorite, onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: EhbrColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
            child: Row(
              children: [
                SizedBox(width: 26, child: Icon(item.icon, size: 24, color: EhbrColors.ink)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: manrope(12, FontWeight.w700, EhbrColors.ink)),
                      const SizedBox(height: 3),
                      Text('${item.number} · ${item.subtitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: manrope(11, FontWeight.w600, EhbrColors.ink.withValues(alpha: .55))),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded, color: favorite ? EhbrColors.brand : EhbrColors.muted),
                ),
                Material(
                  color: EhbrColors.brand,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => confirmCall(context, item.name, item.number),
                    child: SizedBox(
                      width: 60,
                      height: 30,
                      child: Center(child: Text('CALL', style: manrope(12, FontWeight.w600, Colors.white))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
