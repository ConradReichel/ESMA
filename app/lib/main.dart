import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'auth.dart';

void main() => runApp(const EsmaApp());

const ink = Color(0xFF20372D);
const forest = Color(0xFF315E49);
const cream = Color(0xFFF5F6F0);
const line = Color(0xFFE7E9E1);

class EsmaApp extends StatelessWidget {
  const EsmaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ESMA · Hühnerpatenmanager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: cream,
          colorScheme: ColorScheme.fromSeed(seedColor: forest, surface: cream, primary: forest),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final api = EsmaApi();
  String section = 'Übersicht';
  bool loading = true;
  bool signedIn = false;
  String? error;
  String userName = 'Vereinsverwaltung';
  List<Map<String, dynamic>> chickens = [];
  List<Map<String, dynamic>> inquiries = [];
  List<Map<String, dynamic>> sponsorships = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      if (await initAuth()) {
        if (mounted) setState(() { signedIn = true; userName = authUsername(); });
        await _load();
      }
    } catch (_) { /* Die statische Seite ist lokal oder noch nicht angemeldet. */ }
  }

  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      if (signedIn) {
        final results = await Future.wait([
          api.get('/api/v1/admin/chickens'),
          api.get('/api/v1/admin/requests'),
          api.get('/api/v1/admin/sponsorships'),
        ]);
        chickens = _items(results[0]); inquiries = _items(results[1]); sponsorships = _items(results[2]);
      } else {
        chickens = _items(await api.get('/api/v1/public/chickens'));
      }
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> data) => (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
  void _signIn() => authLogin();
  void _signOut() => authLogout();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;
    return Scaffold(
      drawer: compact ? Drawer(child: _nav()) : null,
      body: Row(children: [
        if (!compact) SizedBox(width: 248, child: _nav()),
        Expanded(child: Column(children: [
          _topBar(compact),
          Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : _content()),
        ])),
      ]),
    );
  }

  Widget _nav() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(22, 28, 16, 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.egg_alt_rounded, color: Colors.white)),
        const SizedBox(width: 11),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ESMA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: ink)), Text('Patenmanager', style: TextStyle(fontSize: 11, color: Colors.black54))]),
      ]),
      const SizedBox(height: 42),
      const Text('ARBEITSBEREICH', style: TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Colors.black38)),
      const SizedBox(height: 12),
      _navItem('Übersicht', Icons.grid_view_rounded),
      _navItem('Hühner', Icons.egg_alt_outlined, badge: '${chickens.length}'),
      _navItem('Patenschaften', Icons.favorite_border_rounded, badge: '${sponsorships.length}'),
      _navItem('Anfragen', Icons.mark_email_unread_outlined, badge: '${inquiries.where((e) => e['status'] == 'new').length}'),
      const Spacer(),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(14)), child: const Row(children: [Icon(Icons.eco_outlined, color: forest, size: 19), SizedBox(width: 9), Expanded(child: Text('Mit Herz für unsere Hühner', style: TextStyle(color: ink, fontSize: 11, height: 1.3)))])),
      const SizedBox(height: 17),
      Row(children: [const CircleAvatar(radius: 16, backgroundColor: Color(0xFFE8EEE5), child: Icon(Icons.person_outline, size: 18, color: forest)), const SizedBox(width: 9), Expanded(child: Text(signedIn ? userName : 'Nicht angemeldet', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))), if (signedIn) IconButton(tooltip: 'Abmelden', onPressed: _signOut, icon: const Icon(Icons.logout, size: 17))]),
    ]),
  );

  Widget _navItem(String title, IconData icon, {String? badge}) {
    final active = section == title;
    return Padding(padding: const EdgeInsets.only(bottom: 5), child: InkWell(
      borderRadius: BorderRadius.circular(12), onTap: () { setState(() => section = title); if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.pop(context); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), decoration: BoxDecoration(color: active ? const Color(0xFFEAF0E8) : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(icon, size: 19, color: active ? forest : Colors.black45), const SizedBox(width: 12), Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? ink : Colors.black54))), if (badge != null) Text(badge, style: TextStyle(fontSize: 11, color: active ? forest : Colors.black38, fontWeight: FontWeight.w600))])),
    ));
  }

  Widget _topBar(bool compact) => Container(
    height: 76, padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 38), decoration: const BoxDecoration(color: cream, border: Border(bottom: BorderSide(color: line))),
    child: Row(children: [if (compact) Builder(builder: (context) => IconButton(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu))), if (compact) const SizedBox(width: 8), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(section, style: const TextStyle(fontSize: 20, color: ink, fontWeight: FontWeight.w700)), const Text('King Kong e.V.  ·  Hamburg', style: TextStyle(fontSize: 11, color: Colors.black45))])), if (!signedIn) TextButton.icon(onPressed: _signIn, icon: const Icon(Icons.login, size: 17), label: const Text('Anmelden')) else IconButton(tooltip: 'Aktualisieren', onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: forest))]),
  );

  Widget _content() => switch (section) {
    'Hühner' => _chickenPage(),
    'Anfragen' => _inquiryPage(),
    'Patenschaften' => _sponsorshipPage(),
    _ => _dashboard(),
  };

  Widget _dashboard() {
    final available = chickens.where((e) => e['status'] == 'available').length;
    final sponsored = chickens.where((e) => e['status'] == 'sponsored').length;
    final pending = inquiries.where((e) => e['status'] == 'new').length;
    return _pageBody(ListView(padding: const EdgeInsets.fromLTRB(34, 29, 34, 40), children: [
      _hero(available), const SizedBox(height: 24),
      LayoutBuilder(builder: (context, box) { final cols = box.maxWidth < 700 ? 2 : 4; return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: cols, crossAxisSpacing: 13, mainAxisSpacing: 13, childAspectRatio: cols == 2 ? 1.8 : 1.42, children: [
        _stat('Hühner gesamt', '${chickens.length}', Icons.egg_alt_outlined, const Color(0xFFEAF0E8)),
        _stat('Verfügbar', '$available', Icons.wb_sunny_outlined, const Color(0xFFF3EBD8)),
        _stat('Patenschaften', '$sponsored', Icons.favorite_border_rounded, const Color(0xFFF5E6E1)),
        _stat('Neue Anfragen', '$pending', Icons.mark_email_unread_outlined, const Color(0xFFE6ECF1)),
      ]); }),
      const SizedBox(height: 27),
      Row(children: [const Expanded(child: Text('Hühner im Überblick', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink))), TextButton(onPressed: () => setState(() => section = 'Hühner'), child: const Text('Alle anzeigen  →'))]),
      const SizedBox(height: 10),
      if (chickens.isEmpty) _empty('Noch keine Hühnerprofile', 'Lege das erste Profil an, sobald du angemeldet bist.', Icons.egg_outlined) else _chickenTable(chickens.take(5).toList()),
      if (error != null) ...[const SizedBox(height: 14), _errorBanner(error!)],
      if (!signedIn) ...[const SizedBox(height: 18), _infoBanner('Die Verwaltungsdaten sind geschützt. Melde dich mit einem freigeschalteten Vereins-Admin-Konto an.')],
    ]));
  }

  Widget _hero(int count) => Container(
    padding: const EdgeInsets.fromLTRB(27, 26, 20, 24), decoration: BoxDecoration(color: const Color(0xFFE8EEE5), borderRadius: BorderRadius.circular(20)),
    child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), borderRadius: BorderRadius.circular(20)), child: const Text('HOFLEBEN  ·  HAMBURG', style: TextStyle(color: forest, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.1))), const SizedBox(height: 14), const Text('Guten Tag 👋', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink)), const SizedBox(height: 7), Text('$count Hühner freuen sich gerade über eine Patenschaft.', style: const TextStyle(fontSize: 13, color: Color(0xFF667468))), const SizedBox(height: 17), FilledButton.icon(onPressed: signedIn ? _createChicken : _signIn, icon: Icon(signedIn ? Icons.add : Icons.login, size: 17), label: Text(signedIn ? 'Huhn hinzufügen' : 'Als Admin anmelden'), style: FilledButton.styleFrom(backgroundColor: forest, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))])), const SizedBox(width: 12), if (MediaQuery.sizeOf(context).width > 650) Container(width: 126, height: 126, decoration: BoxDecoration(color: const Color(0xFFD7E2D2), borderRadius: BorderRadius.circular(26)), child: const Center(child: Text('🐔', style: TextStyle(fontSize: 71))))]),
  );

  Widget _stat(String title, String value, IconData icon, Color tone) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 17, color: forest)), Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink)), Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54))]));
  Widget _pageBody(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: child));

  Widget _chickenPage() => _pageBody(ListView(padding: const EdgeInsets.fromLTRB(34, 30, 34, 40), children: [
    _pageTitle('Hühnerprofile', 'Stammdaten und Patenschaftsstatus verwalten.', action: signedIn ? FilledButton.icon(onPressed: _createChicken, icon: const Icon(Icons.add, size: 17), label: const Text('Huhn hinzufügen')) : null),
    const SizedBox(height: 21),
    if (chickens.isEmpty) _empty('Keine Profile vorhanden', 'Melde dich als Admin an und lege ein Huhn an.', Icons.egg_outlined) else _chickenTable(chickens),
    if (signedIn) ...[const SizedBox(height: 18), Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: _syncWix, icon: const Icon(Icons.sync, size: 17), label: const Text('Mit Wix synchronisieren')))],
    if (error != null) ...[const SizedBox(height: 14), _errorBanner(error!)],
  ]));

  Widget _chickenTable(List<Map<String, dynamic>> items) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Column(children: [for (var i = 0; i < items.length; i++) _chickenRow(items[i], last: i == items.length - 1)]));

  Widget _chickenRow(Map<String, dynamic> chicken, {bool last = false}) {
    final status = chicken['status']?.toString() ?? 'available';
    return Container(padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: last ? Colors.transparent : line))), child: Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(13), child: Container(width: 42, height: 42, color: const Color(0xFFF0EEE3), child: chicken['imageUrl'] is String && (chicken['imageUrl'] as String).isNotEmpty
        ? Image.network(chicken['imageUrl'] as String, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(chicken['sex'] == 'Hahn' ? '🐓' : '🐔', style: const TextStyle(fontSize: 23))))
        : Center(child: Text(chicken['sex'] == 'Hahn' ? '🐓' : '🐔', style: const TextStyle(fontSize: 23))))),
      const SizedBox(width: 13),
      Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${chicken['name'] ?? 'Unbenannt'}', style: const TextStyle(fontWeight: FontWeight.w700, color: ink)), Text('#${chicken['number'] ?? '—'}  ·  ${chicken['breed'] ?? 'Rasse unbekannt'}', style: const TextStyle(fontSize: 11, color: Colors.black45))])),
      if (MediaQuery.sizeOf(context).width > 620) Expanded(child: Text('${chicken['color'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Colors.black54))),
      _statusChip(status),
      if (signedIn) IconButton(tooltip: 'Profil bearbeiten', onPressed: () => _editChicken(chicken), icon: const Icon(Icons.edit_outlined, size: 18, color: forest)),
      if (!signedIn && status == 'available') IconButton(tooltip: 'Interesse zeigen', onPressed: () => _inquiryForm(chicken), icon: const Icon(Icons.favorite_border, size: 19, color: forest)),
    ]));
  }

  Widget _statusChip(String value) {
    final label = {'available': 'Verfügbar', 'reserved': 'Reserviert', 'sponsored': 'Vergeben', 'inactive': 'Inaktiv', 'new': 'Neu', 'in_progress': 'In Bearbeitung', 'active': 'Aktiv', 'ended': 'Beendet', 'cancelled': 'Beendet', 'accepted': 'Angenommen', 'declined': 'Abgelehnt', 'converted': 'Zugeordnet'}[value] ?? value;
    final color = value == 'available' || value == 'active' ? const Color(0xFF3E7A55) : value == 'sponsored' || value == 'accepted' ? const Color(0xFF9C655A) : const Color(0xFF9A8050);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(30)), child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)));
  }

  Widget _inquiryPage() => _pageBody(ListView(padding: const EdgeInsets.fromLTRB(34, 30, 34, 40), children: [
    _pageTitle('Anfragen', 'Neue Patenschafts- und Wartelistenanfragen bearbeiten.'), const SizedBox(height: 20),
    if (!signedIn) _infoBanner('Bitte melde dich als Vereins-Admin an, um private Anfragedaten zu sehen.')
    else if (inquiries.isEmpty) _empty('Alles auf dem neuesten Stand', 'Neue Anfragen erscheinen hier.', Icons.mark_email_read_outlined)
    else Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Column(children: inquiries.map(_inquiryRow).toList())),
  ]));

  Widget _inquiryRow(Map<String, dynamic> inquiry) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6), leading: const CircleAvatar(backgroundColor: Color(0xFFEAF0E8), child: Icon(Icons.person_outline, color: forest)), title: Text('${inquiry['first_name']} ${inquiry['last_name']}', style: const TextStyle(fontWeight: FontWeight.w700, color: ink)), subtitle: Text('${inquiry['email']}  ·  ${inquiry['chicken_name'] ?? 'Allgemeine Anfrage'}\n${inquiry['message'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis), isThreeLine: true, trailing: PopupMenuButton<String>(tooltip: 'Status ändern', onSelected: (value) => _updateInquiry(inquiry['id'].toString(), value), itemBuilder: (context) => const [PopupMenuItem(value: 'in_progress', child: Text('In Bearbeitung')), PopupMenuItem(value: 'accepted', child: Text('Angenommen')), PopupMenuItem(value: 'declined', child: Text('Abgelehnt')), PopupMenuItem(value: 'converted', child: Text('Patenschaft erstellt'))], child: _statusChip(inquiry['status']?.toString() ?? 'new')));

  Widget _sponsorshipPage() => _pageBody(ListView(padding: const EdgeInsets.fromLTRB(34, 30, 34, 40), children: [
    _pageTitle('Patenschaften', 'Zuordnung, Laufzeit und vereinbarte Beiträge im Blick.', action: signedIn ? FilledButton.icon(onPressed: _createSponsorship, icon: const Icon(Icons.add, size: 17), label: const Text('Patenschaft erfassen')) : null), const SizedBox(height: 20),
    if (!signedIn) _infoBanner('Bitte melde dich als Vereins-Admin an, um Patenschaften zu sehen.')
    else if (sponsorships.isEmpty) _empty('Noch keine Patenschaften', 'Sobald ein Huhn vergeben wird, erscheint die Zuordnung hier.', Icons.favorite_border_rounded)
    else Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Column(children: sponsorships.map((s) => ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFF5E6E1), child: Icon(Icons.favorite_border, color: Color(0xFF9C655A))), title: Text('${s['first_name']} ${s['last_name']}', style: const TextStyle(fontWeight: FontWeight.w700, color: ink)), subtitle: Text('${s['chicken_name']}  ·  ${s['email']}  ·  ${s['starts_on'] ?? 'Beginn offen'}${s['amount_cents'] == null ? '' : '  ·  ${(s['amount_cents'] as num) / 100} €'}'), trailing: PopupMenuButton<String>(tooltip: 'Status ändern', onSelected: (status) async { try { await api.send('PUT', '/api/v1/admin/sponsorships/${s['id']}', {'status': status}); await _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } }, itemBuilder: (context) => const [PopupMenuItem(value: 'active', child: Text('Aktiv')), PopupMenuItem(value: 'ended', child: Text('Beendet')), PopupMenuItem(value: 'cancelled', child: Text('Gekündigt'))], child: _statusChip(s['status']?.toString() ?? 'active')))).toList())),
  ]));

  Widget _pageTitle(String title, String subtitle, {Widget? action}) => Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink)), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54))])), if (action != null) action]);
  Widget _empty(String title, String message, IconData icon) => Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Column(children: [Icon(icon, size: 34, color: const Color(0xFF9BB58C)), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: ink)), const SizedBox(height: 5), Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black45))]));
  Widget _infoBanner(String message) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFE8EEF2), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.info_outline, color: Color(0xFF476478), size: 19), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF476478), fontSize: 12)))]));
  Widget _errorBanner(String message) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF9E9E5), borderRadius: BorderRadius.circular(12)), child: Text(message, style: const TextStyle(color: Color(0xFF9C5145), fontSize: 12)));

  Future<void> _createChicken() => _editChicken({});

  Future<void> _inquiryForm(Map<String, dynamic> chicken) async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => InquiryDialog(chicken: chicken));
    if (result == null) return;
    try {
      await api.send('POST', '/api/v1/public/requests', result);
      if (mounted) showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Vielen Dank!'), content: const Text('Deine Anfrage ist beim Verein angekommen. Wir melden uns bei dir.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))]));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }

  Future<void> _createSponsorship() async {
    if (!signedIn) { _signIn(); return; }
    if (chickens.isEmpty) return;
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => SponsorshipDialog(chickens: chickens));
    if (result == null) return;
    try { await api.send('POST', '/api/v1/admin/sponsorships', result); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }

  Future<void> _editChicken(Map<String, dynamic> initial) async {
    if (!signedIn) { _signIn(); return; }
    final values = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => ChickenDialog(initial: initial));
    if (values == null) return;
    try { if (initial['id'] == null) { await api.send('POST', '/api/v1/admin/chickens', values); } else { await api.send('PUT', '/api/v1/admin/chickens/${initial['id']}', values); } await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }
  Future<void> _updateInquiry(String id, String status) async { try { await api.send('PUT', '/api/v1/admin/requests/$id', {'status': status}); await _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } }
  Future<void> _syncWix() async { try { final r = await api.send('POST', '/api/v1/admin/wix/sync'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r['synced']} Profile synchronisiert, ${r['failed']} Fehler.'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } }
}

class InquiryDialog extends StatefulWidget {
  const InquiryDialog({super.key, required this.chicken});
  final Map<String, dynamic> chicken;
  @override State<InquiryDialog> createState() => _InquiryDialogState();
}

class _InquiryDialogState extends State<InquiryDialog> {
  final first = TextEditingController(), last = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), message = TextEditingController();
  bool accepted = false;
  @override void dispose() { first.dispose(); last.dispose(); email.dispose(); phone.dispose(); message.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text('Interesse an ${widget.chicken['name']}', style: const TextStyle(color: ink)),
    content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Align(alignment: Alignment.centerLeft, child: Text('Schreib uns ein paar Zeilen. Das Team meldet sich persönlich bei dir.', style: TextStyle(color: Colors.black54, fontSize: 13))), const SizedBox(height: 17),
      Row(children: [Expanded(child: TextField(controller: first, decoration: const InputDecoration(labelText: 'Vorname *'))), const SizedBox(width: 10), Expanded(child: TextField(controller: last, decoration: const InputDecoration(labelText: 'Nachname *')))]), const SizedBox(height: 12),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-Mail *')), const SizedBox(height: 12),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon (optional)')), const SizedBox(height: 12),
      TextField(controller: message, maxLines: 3, decoration: const InputDecoration(labelText: 'Nachricht (optional)')),
      CheckboxListTile(contentPadding: EdgeInsets.zero, value: accepted, onChanged: (v) => setState(() => accepted = v ?? false), title: const Text('Ich habe den Datenschutzhinweis zur Kenntnis genommen.', style: TextStyle(fontSize: 11)), controlAffinity: ListTileControlAffinity.leading),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')), FilledButton(onPressed: accepted && first.text.trim().isNotEmpty && last.text.trim().isNotEmpty && email.text.contains('@') ? () => Navigator.pop(context, {'chickenId': widget.chicken['id'], 'firstName': first.text.trim(), 'lastName': last.text.trim(), 'email': email.text.trim(), 'phone': phone.text.trim(), 'message': message.text.trim(), 'privacyAccepted': accepted}) : null, child: const Text('Anfrage senden'))],
  );
}

class SponsorshipDialog extends StatefulWidget {
  const SponsorshipDialog({super.key, required this.chickens});
  final List<Map<String, dynamic>> chickens;
  @override State<SponsorshipDialog> createState() => _SponsorshipDialogState();
}

class _SponsorshipDialogState extends State<SponsorshipDialog> {
  final first = TextEditingController(), last = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), amount = TextEditingController(), starts = TextEditingController(), ends = TextEditingController();
  late String chickenId = widget.chickens.first['id'].toString();
  String frequency = 'Monatlich';
  @override void dispose() { first.dispose(); last.dispose(); email.dispose(); phone.dispose(); amount.dispose(); starts.dispose(); ends.dispose(); super.dispose(); }
  Widget field(TextEditingController c, String label, {TextInputType? type}) => Padding(padding: const EdgeInsets.only(bottom: 11), child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label)));
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Patenschaft erfassen', style: TextStyle(color: ink)),
    content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(initialValue: chickenId, decoration: const InputDecoration(labelText: 'Huhn'), items: widget.chickens.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text('${c['name']} · #${c['number']}'))).toList(), onChanged: (v) => setState(() => chickenId = v ?? chickenId)), const SizedBox(height: 12),
      Row(children: [Expanded(child: field(first, 'Vorname *')), const SizedBox(width: 10), Expanded(child: field(last, 'Nachname *'))]),
      field(email, 'E-Mail *', type: TextInputType.emailAddress), field(phone, 'Telefon'),
      Row(children: [Expanded(child: field(starts, 'Beginn (JJJJ-MM-TT)')), const SizedBox(width: 10), Expanded(child: field(ends, 'Ende (optional)'))]),
      Row(children: [Expanded(child: field(amount, 'Beitrag in €', type: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(initialValue: frequency, decoration: const InputDecoration(labelText: 'Rhythmus'), items: const [DropdownMenuItem(value: 'Monatlich', child: Text('Monatlich')), DropdownMenuItem(value: 'Jährlich', child: Text('Jährlich')), DropdownMenuItem(value: 'Einmalig', child: Text('Einmalig'))], onChanged: (v) => setState(() => frequency = v ?? frequency)))])
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')), FilledButton(onPressed: first.text.trim().isNotEmpty && last.text.trim().isNotEmpty && email.text.contains('@') ? () => Navigator.pop(context, {'chickenId': chickenId, 'firstName': first.text.trim(), 'lastName': last.text.trim(), 'email': email.text.trim(), 'phone': phone.text.trim(), 'startsOn': starts.text.trim().isEmpty ? null : starts.text.trim(), 'endsOn': ends.text.trim().isEmpty ? null : ends.text.trim(), 'amount': double.tryParse(amount.text.replaceAll(',', '.')), 'paymentFrequency': frequency, 'status': 'active'}) : null, child: const Text('Patenschaft speichern'))],
  );
}

class ChickenDialog extends StatefulWidget {
  const ChickenDialog({super.key, required this.initial});
  final Map<String, dynamic> initial;
  @override State<ChickenDialog> createState() => _ChickenDialogState();
}

class _ChickenDialogState extends State<ChickenDialog> {
  late final fields = <String, TextEditingController>{for (final key in ['number', 'name', 'ringNumber', 'breed', 'sex', 'color', 'hatchYear', 'description']) key: TextEditingController(text: widget.initial[key]?.toString() ?? '')};
  late String status = widget.initial['status']?.toString() ?? 'available';
  late bool published = widget.initial['published'] == true;
  Uint8List? imageBytes;
  String? imageMimeType;
  bool clearImage = false;
  bool picking = false;
  @override void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  Widget input(String key, String label, {int lines = 1}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: fields[key], maxLines: lines, decoration: InputDecoration(labelText: label)));
  Future<void> _pickImage() async {
    try {
      setState(() => picking = true);
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp']);
      if (file == null || !mounted) return;
      final size = file.lengthSync() ?? await file.length();
      if (!mounted) return;
      if (size == null) throw Exception('Die Bildgröße konnte nicht gelesen werden.');
      if (size > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bilder dürfen höchstens 5 MB groß sein.')));
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) throw Exception('Die Bilddatei konnte nicht gelesen werden.');
      final extension = file.extension?.toLowerCase();
      final mime = switch (extension) { 'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp', _ => null };
      if (mime == null) throw Exception('Bitte wähle ein JPG-, PNG- oder WebP-Bild.');
      setState(() { imageBytes = bytes; imageMimeType = mime; clearImage = false; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }
  Widget _imageControl() {
    final existingUrl = widget.initial['imageUrl']?.toString() ?? '';
    Widget preview;
    if (imageBytes != null) {
      preview = Image.memory(imageBytes!, width: 78, height: 70, fit: BoxFit.cover);
    } else if (existingUrl.isNotEmpty && !clearImage) {
      preview = Image.network(existingUrl, width: 78, height: 70, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
    } else {
      preview = const Icon(Icons.add_a_photo_outlined, color: forest, size: 26);
    }
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(width: 78, height: 70, color: const Color(0xFFF0EEE3), alignment: Alignment.center, child: preview)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(imageBytes != null ? 'Neues Bild ausgewählt' : existingUrl.isNotEmpty && !clearImage ? 'Hühnerbild' : 'Noch kein Bild', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3), const Text('JPG, PNG oder WebP · bis 5 MB', style: TextStyle(fontSize: 11, color: Colors.black54)),
        Wrap(spacing: 4, children: [TextButton.icon(onPressed: picking ? null : _pickImage, icon: Icon(picking ? Icons.hourglass_empty : Icons.upload_outlined, size: 16), label: Text(picking ? 'Lädt …' : 'Bild auswählen')), if ((imageBytes != null || (existingUrl.isNotEmpty && !clearImage))) TextButton(onPressed: () => setState(() { imageBytes = null; imageMimeType = null; clearImage = true; }), child: const Text('Entfernen'))]),
      ])),
    ]));
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial['id'] == null ? 'Huhn anlegen' : 'Huhn bearbeiten', style: const TextStyle(color: ink)),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Expanded(child: input('number', 'Huhnnummer *')), const SizedBox(width: 12), Expanded(child: input('name', 'Name *'))]),
      Row(children: [Expanded(child: input('breed', 'Rasse')), const SizedBox(width: 12), Expanded(child: input('hatchYear', 'Schlupfjahr'))]),
      Row(children: [Expanded(child: input('ringNumber', 'Ringnummer')), const SizedBox(width: 12), Expanded(child: input('color', 'Farbe'))]),
      _imageControl(), input('description', 'Kurzbeschreibung', lines: 3),
      DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Status'), items: const [DropdownMenuItem(value: 'available', child: Text('Verfügbar')), DropdownMenuItem(value: 'reserved', child: Text('Reserviert')), DropdownMenuItem(value: 'sponsored', child: Text('Vergeben')), DropdownMenuItem(value: 'inactive', child: Text('Inaktiv'))], onChanged: (v) => setState(() => status = v ?? 'available')),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Auf der Website veröffentlichen', style: TextStyle(fontSize: 13)), value: published, onChanged: (v) => setState(() => published = v)),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')), FilledButton(onPressed: picking ? null : () {
      final values = <String, dynamic>{'number': fields['number']!.text, 'name': fields['name']!.text, 'ringNumber': fields['ringNumber']!.text, 'breed': fields['breed']!.text, 'sex': fields['sex']!.text.isEmpty ? 'Huhn' : fields['sex']!.text, 'color': fields['color']!.text, 'hatchYear': int.tryParse(fields['hatchYear']!.text), 'description': fields['description']!.text, 'status': status, 'published': published};
      if (imageBytes != null) { values['imageData'] = base64Encode(imageBytes!); values['imageMimeType'] = imageMimeType; }
      if (clearImage) values['clearImage'] = true;
      Navigator.pop(context, values);
    }, child: const Text('Speichern'))],
  );
}
