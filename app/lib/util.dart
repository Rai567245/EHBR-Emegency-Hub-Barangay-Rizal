/// "just now", "5m ago", "3h ago", "2d ago", or a short date.
String ago(DateTime d) {
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  if (s < 86400 * 14) return '${s ~/ 86400}d ago';
  return shortDate(d);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String stamp(DateTime d) {
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '${shortDate(d)}, $h12:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
}

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
