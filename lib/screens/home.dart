// App shell laid out like the Immich web client: top bar with search, upload and
// account menu; a labelled sidebar; storage and server status at the bottom.
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../backup.dart';
import '../desktop_integration.dart';
import '../i18n.dart';
import '../sources.dart';
import '../settings.dart';
import '../window.dart';
import '../widgets/search_filter_dialog.dart';
import '../widgets/brand.dart';
import '../widgets/asset_actions.dart';
import '../widgets/loader.dart';
import '../widgets/memories.dart';
import '../widgets/timeline_view.dart';
import '../widgets/upload_dialog.dart';
import 'albums.dart';
import 'account_settings.dart';
import 'admin.dart';
import 'locked_folder.dart';
import 'utilities.dart';
import 'backup_screen.dart';
import 'explore.dart';
import 'library_extra.dart';
import 'map_screen.dart';
import 'search.dart';

enum _Page {
  photos, explore, map, memories, people, sharedLinks, sharing, favorites, albums, tags, recent, folders,
  utilities, archive, locked, trash, backup, search, account, admin,
}

class _NavEntry {
  final _Page page;
  final String labelKey;
  String get label => t(labelKey);
  final IconData icon;
  final IconData selectedIcon;
  const _NavEntry(this.page, this.labelKey, this.icon, this.selectedIcon);
}

/// Sidebar entries in the web's order (UserSidebar.svelte); optional ones follow
/// the user's "show in sidebar" preferences, like the web.
(List<_NavEntry>, List<_NavEntry>) _navFor(Map<String, dynamic> prefs) {
  bool on(String group, [String key = 'enabled']) => (prefs[group] as Map?)?[key] == true;
  bool side(String group) => (group == 'recentlyAdded' || on(group)) && on(group, 'sidebarWeb');
  return (
    [
      const _NavEntry(_Page.photos, 'photos', Icons.photo_library_outlined, Icons.photo_library),
      const _NavEntry(_Page.explore, 'explore', Icons.search, Icons.search),
      const _NavEntry(_Page.map, 'map', Icons.map_outlined, Icons.map),
      if (side('memories')) const _NavEntry(_Page.memories, 'memories', Icons.style_outlined, Icons.style),
      if (side('people')) const _NavEntry(_Page.people, 'people', Icons.person_outline, Icons.person),
      if (side('sharedLinks')) const _NavEntry(_Page.sharedLinks, 'shared_links', Icons.link, Icons.link),
      const _NavEntry(_Page.sharing, 'sharing', Icons.group_outlined, Icons.group),
    ],
    [
      const _NavEntry(_Page.favorites, 'favorites', Icons.favorite_border, Icons.favorite),
      const _NavEntry(_Page.albums, 'albums', Icons.photo_album_outlined, Icons.photo_album),
      if (side('tags')) const _NavEntry(_Page.tags, 'tags', Icons.sell_outlined, Icons.sell),
      if (side('recentlyAdded'))
        const _NavEntry(_Page.recent, 'recently_added', Icons.schedule_outlined, Icons.schedule),
      if (side('folders')) const _NavEntry(_Page.folders, 'folders', Icons.folder_outlined, Icons.folder),
      const _NavEntry(_Page.utilities, 'utilities', Icons.handyman_outlined, Icons.handyman),
      const _NavEntry(_Page.archive, 'archive', Icons.archive_outlined, Icons.archive),
      const _NavEntry(_Page.locked, 'locked_folder', Icons.lock_outline, Icons.lock),
      const _NavEntry(_Page.trash, 'trash', Icons.delete_outline, Icons.delete),
    ],
  );
}

const _deviceNav = [
  _NavEntry(_Page.backup, 'backup', Icons.backup_outlined, Icons.backup),
];

class HomeScreen extends StatefulWidget {
  final ImmichApi api;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.api, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Page _page = _Page.photos;
  // Bumped by "refresh" to rebuild every page from scratch.
  int _generation = 0;
  late final Future<Map<String, dynamic>> _me = widget.api.me();
  Map<String, dynamic> _prefs = const {};
  late final Future<BackupService> _backup = _startBackup();
  final _searchCtl = TextEditingController();
  SearchFilter _filter = SearchFilter(); // a new instance per search, so results reload

  Future<BackupService> _startBackup() async {
    final me = await _me;
    final service = BackupService(widget.api, userId: me['id']);
    await service.init();
    return service;
  }

  StreamSubscription<String>? _trayActions;
  StreamSubscription<List<String>>? _drops;

  @override
  void dispose() {
    _trayActions?.cancel();
    _drops?.cancel();
    settings.removeListener(_applyDesktopSettings);
    i18n.removeListener(_setupTray);
    _backup.then((s) => s.dispose()).catchError((_) {});
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // Tray menu, close-to-tray and drag & drop upload (GTK runner).
    _trayActions = trayActions.listen((action) async {
      if (action == 'backup') (await _backup).runNow();
    });
    _drops = droppedFiles.listen((paths) async {
      if (mounted && await uploadDropped(context, widget.api, paths)) _refresh();
    });
    _setupTray();
    _applyDesktopSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkMenuEntry());
    settings.addListener(_applyDesktopSettings);
    i18n.addListener(_setupTray); // menu labels follow the language
  }

  void _setupTray() => setTray([
        ('open', t('linux_tray_open')),
        ('backup', t('linux_backup_now')),
        ('', ''),
        ('quit', t('linux_tray_quit')),
      ]);

  void _applyDesktopSettings() => setCloseToTray(settings.closeToTray);

  /// AppImage: keep its menu entry pointing at the current file, and offer one
  /// once (without it GNOME shows a generic icon and the raw app id).
  Future<void> _checkMenuEntry() async {
    final state = await menuEntryState();
    if (state == MenuEntryState.outdated) return installMenuEntry(); // moved / updated AppImage
    if (state != MenuEntryState.missing || settings.menuEntryAsked || !mounted) return;
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.app_registration),
        title: Text(t('linux_menu_entry_title')),
        content: Text(t('linux_menu_entry_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('linux_not_now'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('linux_menu_entry_add'))),
        ],
      ),
    );
    await settings.update(menuEntryAsked: true);
    if (add == true) await installMenuEntry();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await widget.api.preferences();
      if (mounted) setState(() => _prefs = p);
    } catch (_) {}
  }

  void _go(_Page p) {
    setState(() => _page = p);
    // Sidebar options may have just been changed in Account Settings.
    if (p != _Page.account) _loadPrefs();
  }

  void _refresh() => setState(() => _generation++);

  void _search() {
    final f = _filter.copy()..query = _searchCtl.text.trim();
    if (f.isEmpty) return;
    setState(() {
      _filter = f;
      _page = _Page.search;
    });
  }

  Future<void> _openFilters() async {
    final f = await showSearchFilterDialog(context, widget.api, _filter.copy()..query = _searchCtl.text);
    if (f == null || !mounted) return;
    _searchCtl.text = f.query;
    setState(() {
      _filter = f;
      if (!f.isEmpty) _page = _Page.search;
    });
  }

  Future<void> _upload() async {
    if (await pickAndUpload(context, widget.api)) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      body: Column(children: [
        _TopBar(
          api: widget.api,
          me: _me,
          searchCtl: _searchCtl,
          byFilename: _filter.mode == SearchMode.filename,
          filterCount: _filter.filterCount,
          onToggleFilename: () {
            setState(() => _filter = _filter.copy()
              ..mode = _filter.mode == SearchMode.filename ? SearchMode.smart : SearchMode.filename);
            if (_page == _Page.search) _search();
          },
          onFilters: _openFilters,
          onSearch: _search,
          onUpload: _upload,
          onRefresh: _refresh,
          onLogout: widget.onLogout,
          onOpen: _go,
        ),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Sidebar(
              nav: _navFor(_prefs),
              wide: wide,
              current: _page,
              onSelect: _go,
              api: widget.api,
              backup: _backup,
            ),
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                KeyedSubtree(key: ValueKey(_generation), child: _buildPage()),
                const _DropHint(),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPage() {
    final api = widget.api;
    switch (_page) {
      case _Page.photos:
        return _TimelinePage(api: api, query: TimelineQuery.photos,
            emptyText: t('no_assets_to_show'), showMemories: true);
      case _Page.explore:
        return _Titled(t('explore'), child: ExploreScreen(api: api));
      case _Page.map:
        return _Titled(t('map'), child: MapScreen(api: api));
      case _Page.sharing:
        return _Titled(t('sharing'),
            action: TextButton.icon(
              onPressed: () => _go(_Page.sharedLinks),
              icon: const Icon(Icons.link),
              label: Text(t('shared_links')),
            ),
            child: _SharingPage(api: api));
      case _Page.favorites:
        return _Titled(t('favorites'),
            child: _TimelinePage(api: api, query: TimelineQuery.favorites,
                emptyText: t('no_favorites_message')));
      case _Page.albums:
        return _Titled(t('albums'), child: AlbumsScreen(api: api));
      case _Page.archive:
        return _Titled(t('archive'),
            child: _TimelinePage(api: api, query: TimelineQuery.archive,
                emptyText: t('no_archived_assets_message'), mode: TimelineMode.archive));
      case _Page.trash:
        return _Titled(t('trash'), child: _TrashPage(api: api));
      case _Page.backup:
        return _Titled(t('backup'),
            child: FutureBuilder<BackupService>(
              future: _backup,
              builder: (context, snap) => snap.hasError
                  ? Center(child: Text('${t('error')}: ${snap.error}'))
                  : !snap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : BackupScreen(service: snap.data!),
            ));
      case _Page.people:
        return PeopleScreen(api: api);
      case _Page.memories:
        return MemoriesScreen(api: api);
      case _Page.sharedLinks:
        return _Titled(t('shared_links'), child: SharedLinksScreen(api: api));
      case _Page.tags:
        return _Titled(t('tags'), child: TagsScreen(api: api));
      case _Page.recent:
        return _Titled(t('recently_added'),
            child: _TimelinePage(api: api, query: TimelineQuery.recent, emptyText: t('no_assets_to_show')));
      case _Page.folders:
        return _Titled(t('folders'), child: FoldersScreen(api: api));
      case _Page.utilities:
        return _Titled(t('utilities'), child: UtilitiesScreen(api: api));
      case _Page.locked:
        return _Titled(t('locked_folder'), child: LockedFolderScreen(api: api));
      case _Page.account:
        return _Titled(t('settings'), child: AccountSettingsScreen(api: api));
      case _Page.admin:
        return _Titled(t('administration'), child: AdminScreen(api: api));
      case _Page.search:
        return _Titled(
          _filter.query.isEmpty ? t('search') : t('linux_search_title', {'query': _filter.query}),
          action: TextButton.icon(
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
            label: Text(t('search_options')),
          ),
          child: SearchResults(api: api, filter: _filter),
        );
    }
  }
}

/// Page title row with a divider, like the web's page headers.
class _Titled extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const _Titled(this.title, {required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, action != null ? 8 : 18, 16, action != null ? 4 : 14),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?action,
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: child),
    ]);
  }
}

class _TimelinePage extends StatefulWidget {
  final ImmichApi api;
  final TimelineQuery query;
  final String emptyText;
  final TimelineMode mode;
  final bool showMemories;
  const _TimelinePage({
    super.key,
    required this.api,
    required this.query,
    required this.emptyText,
    this.mode = TimelineMode.normal,
    this.showMemories = false,
  });

  @override
  State<_TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<_TimelinePage> {
  late Future<TimelineSource> _source = TimelineSource.create(widget.api, widget.query);
  List<Map<String, dynamic>> _memories = const [];

  @override
  void initState() {
    super.initState();
    if (widget.showMemories) _loadMemories();
  }

  Future<void> _loadMemories() async {
    try {
      final prefs = await widget.api.preferences();
      if ((prefs['memories'] as Map?)?['enabled'] == false) return;
      final list = (await widget.api.memories())
          .where((m) => (m['assets'] as List?)?.isNotEmpty ?? false)
          .toList();
      if (mounted) setState(() => _memories = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Loader<TimelineSource>(
      future: _source,
      onRetry: () => setState(() { _source = TimelineSource.create(widget.api, widget.query); }),
      builder: (src) => TimelineView(
        api: widget.api,
        source: src,
        emptyText: widget.emptyText,
        mode: widget.mode,
        header: _memories.isEmpty ? null : MemoryLane(api: widget.api, memories: _memories),
        headerExtent: 220,
      ),
    );
  }
}

class _TrashPage extends StatefulWidget {
  final ImmichApi api;
  const _TrashPage({required this.api});

  @override
  State<_TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<_TrashPage> {
  late final Future<int> _days = widget.api.trashDays();
  int _generation = 0;

  Future<void> _bulk({required bool restore}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(restore ? t('restore_all') : t('empty_trash')),
        content: Text(restore
            ? t('assets_restore_confirmation')
            : t('empty_trash_confirmation')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            style: restore
                ? null
                : FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(restore ? t('restore') : t('empty_trash')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      restore ? await widget.api.restoreAllTrash() : await widget.api.emptyTrash();
      messenger.showSnackBar(SnackBar(
          content: Text(restore ? t('linux_trash_restored') : t('linux_trash_emptied'))));
      setState(() => _generation++);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(
            child: FutureBuilder<int>(
              future: _days,
              builder: (context, snap) => Text(
                snap.hasData
                    ? t('trashed_items_will_be_permanently_deleted_after', {'days': snap.data})
                    : '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _bulk(restore: true),
            icon: const Icon(Icons.restore_from_trash_outlined),
            label: Text(t('restore_all')),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => _bulk(restore: false),
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(t('empty_trash')),
          ),
        ]),
      ),
      Expanded(
        child: _TimelinePage(
          key: ValueKey(_generation),
          api: widget.api,
          query: TimelineQuery.trash,
          emptyText: t('trash_no_results_message'),
          mode: TimelineMode.trash,
        ),
      ),
    ]);
  }
}

class _SharingPage extends StatefulWidget {
  final ImmichApi api;
  const _SharingPage({required this.api});

  @override
  State<_SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<_SharingPage> {
  late final Future<List<Partner>> _partners = widget.api.partners('shared-with');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = widget.api;
    return ListView(children: [
      FutureBuilder<List<Partner>>(
        future: _partners,
        builder: (context, snap) {
          final partners = snap.data ?? const [];
          if (partners.isEmpty) return const SizedBox();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(t('partners'), style: theme.textTheme.titleMedium),
            ),
            Wrap(children: [
              for (final p in partners)
                SizedBox(
                  width: 320,
                  child: ListTile(
                    leading: _Avatar(api: api, userId: p.id, name: p.name, radius: 20),
                    title: Text(p.name),
                    subtitle: Text(p.email),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TimelineScreen(
                        api: api,
                        title: p.name,
                        query: TimelineQuery(userId: p.id),
                        mode: TimelineMode.readOnly,
                      ),
                    )),
                  ),
                ),
            ]),
          ]);
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(t('albums'), style: theme.textTheme.titleMedium),
      ),
      AlbumsScreen(api: api, sharedOnly: true),
    ]);
  }
}

class _Avatar extends StatelessWidget {
  final ImmichApi api;
  final String userId;
  final String name;
  final double radius;
  final String? changedAt;
  const _Avatar({
    required this.api,
    required this.userId,
    required this.name,
    required this.radius,
    this.changedAt,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipOval(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: scheme.primary,
        alignment: Alignment.center,
        child: Image(
          image: NetworkImage(api.profileImageUrl(userId, changedAt: changedAt),
              headers: api.headers),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          // No profile picture uploaded: show the initial, like the web.
          errorBuilder: (_, _, _) => Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(color: scheme.onPrimary, fontSize: radius, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ImmichApi api;
  final Future<Map<String, dynamic>> me;
  final TextEditingController searchCtl;
  final bool byFilename;
  final int filterCount;
  final VoidCallback onToggleFilename;
  final VoidCallback onFilters;
  final VoidCallback onSearch;
  final VoidCallback onUpload;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;
  final ValueChanged<_Page> onOpen;

  const _TopBar({
    required this.api,
    required this.me,
    required this.searchCtl,
    required this.byFilename,
    required this.filterCount,
    required this.onToggleFilename,
    required this.onFilters,
    required this.onSearch,
    required this.onUpload,
    required this.onRefresh,
    required this.onLogout,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(children: [
        SizedBox(
          width: 216,
          child: Align(
            alignment: Alignment.centerLeft,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: FotorollLogo(size: 36),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: TextField(
                controller: searchCtl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: InputDecoration(
                  hintText: byFilename ? t('search_by_filename') : t('search_your_photos'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      FilterChip(
                        label: Text(t('filename')),
                        selected: byFilename,
                        showCheckmark: false,
                        onSelected: (_) => onToggleFilename(),
                        shape: const StadiumBorder(),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: t('search_options'),
                        onPressed: onFilters,
                        icon: Badge(
                          isLabelVisible: filterCount > 0,
                          label: Text('$filterCount'),
                          child: const Icon(Icons.tune),
                        ),
                      ),
                    ]),
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        TextButton.icon(
          onPressed: onUpload,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(t('upload')),
        ),
        IconButton(tooltip: t('refresh'), onPressed: onRefresh, icon: const Icon(Icons.refresh)),
        const SizedBox(width: 8),
        FutureBuilder<Map<String, dynamic>>(
          future: me,
          builder: (context, snap) {
            final u = snap.data;
            if (u == null) return const SizedBox(width: 44);
            final menu = MenuController();
            void open(_Page p) {
              menu.close();
              onOpen(p);
            }
            // Web: AccountInfoPanel — rounded panel, profile card on top, sign out below.
            final card = scheme.primary.withValues(alpha: 0.10);
            Widget pill(IconData icon, String label, VoidCallback onTap) => SizedBox(
                  width: 220,
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: Icon(icon, size: 18),
                    label: Text(label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      backgroundColor: scheme.surfaceContainerHighest,
                      side: BorderSide(color: scheme.outlineVariant),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                );
            return MenuAnchor(
              controller: menu,
              alignmentOffset: const Offset(-316, 8),
              style: MenuStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
                elevation: const WidgetStatePropertyAll(8),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                )),
              ),
              menuChildren: [
                SizedBox(
                  width: 360,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6)),
                        ),
                        child: Column(children: [
                          _Avatar(api: api, userId: u['id'], name: u['name'] ?? '', radius: 40,
                              changedAt: u['profileChangedAt']),
                          const SizedBox(height: 14),
                          Text(u['name'] ?? '',
                              style: theme.textTheme.titleLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(u['email'] ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 20),
                          pill(Icons.settings_outlined, t('account_settings'), () => open(_Page.account)),
                          if (u['isAdmin'] == true) ...[
                            const SizedBox(height: 8),
                            pill(Icons.build_outlined, t('administration'), () => open(_Page.admin)),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Material(
                        color: card,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            menu.close();
                            onLogout();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.logout, size: 20),
                              const SizedBox(width: 10),
                              Text(t('sign_out'), style: theme.textTheme.titleSmall),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
              builder: (context, ctl, _) => InkWell(
                customBorder: const CircleBorder(),
                onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
                child: _Avatar(api: api, userId: u['id'], name: u['name'] ?? '', radius: 22,
                    changedAt: u['profileChangedAt']),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final (List<_NavEntry>, List<_NavEntry>) nav;
  final bool wide;
  final _Page current;
  final ValueChanged<_Page> onSelect;
  final ImmichApi api;
  final Future<BackupService> backup;

  const _Sidebar({
    required this.nav,
    required this.wide,
    required this.current,
    required this.onSelect,
    required this.api,
    required this.backup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String label) => wide
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
            child: Text(label, style: theme.textTheme.labelMedium),
          )
        : const Divider(indent: 16, endIndent: 16, height: 24);

    return SizedBox(
      width: wide ? 256 : 76,
      child: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.only(top: 12, right: 16), children: [
            for (final e in nav.$1) _navItem(context, e),
            section(t('library')),
            for (final e in nav.$2) _navItem(context, e),
            section(t('linux_this_device')),
            for (final e in _deviceNav) _navItem(context, e),
          ]),
        ),
        if (wide) _StorageCard(api: api),
      ]),
    );
  }

  Widget _navItem(BuildContext context, _NavEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final selected = current == e.page;
    Widget icon = Icon(selected ? e.selectedIcon : e.icon,
        color: selected ? scheme.primary : scheme.onSurface);
    if (e.page == _Page.backup) icon = _BackupBadge(backup: backup, child: icon);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
        child: InkWell(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
          onTap: () => onSelect(e.page),
          child: Tooltip(
            message: wide ? '' : e.label,
            child: Padding(
              // Narrow rail: 76 px minus the list's 16 px right padding leaves 60 = 18 + 24 + 18.
              padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 18, vertical: 14),
              child: Row(children: [
                icon,
                if (wide) ...[
                  const SizedBox(width: 18),
                  Text(e.label,
                      style: TextStyle(
                        fontSize: 15,
                        color: selected ? scheme.primary : scheme.onSurface,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      )),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupBadge extends StatelessWidget {
  final Future<BackupService> backup;
  final Widget child;
  const _BackupBadge({required this.backup, required this.child});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BackupService>(
      future: backup,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return child;
        return ListenableBuilder(
          listenable: s,
          builder: (context, _) => Badge(
            isLabelVisible: s.isRunning || s.errors.isNotEmpty,
            smallSize: 8,
            backgroundColor: !s.isRunning && s.errors.isNotEmpty
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            child: child,
          ),
        );
      },
    );
  }
}

class _StorageCard extends StatefulWidget {
  final ImmichApi api;
  const _StorageCard({required this.api});

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  late final Future<ServerStorage> _storage = widget.api.serverStorage();
  late final Future<String> _version = widget.api.serverVersion();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FutureBuilder<ServerStorage>(
          future: _storage,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) return const SizedBox();
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('storage'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(t('storage_usage', {'used': s.used, 'available': s.size}), style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: s.percent / 100,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ]),
            );
          },
        ),
        const SizedBox(height: 12),
        FutureBuilder<String>(
          future: _version,
          builder: (context, snap) {
            final online = snap.hasData;
            return Row(children: [
              Icon(Icons.circle, size: 10,
                  color: snap.connectionState == ConnectionState.waiting
                      ? Colors.grey
                      : online
                          ? Colors.green
                          : theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(online ? t('server_online') : t('linux_server_offline'),
                  style: theme.textTheme.bodySmall)),
              if (online) Text(snap.data!, style: theme.textTheme.bodySmall),
            ]);
          },
        ),
      ]),
    );
  }
}

/// "Drop to upload" overlay while files are dragged over the window.
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: dragHovering,
      builder: (context, on, _) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.primary, width: 3),
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.file_upload_outlined, size: 72, color: scheme.primary),
                const SizedBox(height: 12),
                Text(t('linux_drop_to_upload'), style: Theme.of(context).textTheme.titleLarge),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
