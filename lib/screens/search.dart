import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../widgets/timeline_view.dart';

/// Results for a query typed into the top search bar.
class SearchResults extends StatefulWidget {
  final ImmichApi api;
  final String query;
  final bool byFilename;

  const SearchResults({
    super.key,
    required this.api,
    required this.query,
    required this.byFilename,
  });

  @override
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  SearchSource? _source;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(SearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.byFilename != widget.byFilename) _start();
  }

  @override
  void dispose() {
    _source?.dispose();
    super.dispose();
  }

  void _start() {
    final q = widget.query.trim();
    final old = _source;
    if (q.isEmpty) {
      _source = null;
    } else {
      final api = widget.api;
      final byName = widget.byFilename;
      _source = SearchSource((page) =>
          byName ? api.filenameSearch(q, page: page) : api.smartSearch(q, page: page))
        ..loadMore();
    }
    // Dispose after the new source is in place so the old view can detach.
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final src = _source;
    if (src == null) {
      return Center(child: Text(t('linux_search_hint')));
    }
    return ListenableBuilder(
      listenable: src,
      builder: (context, _) {
        if (src.error != null && src.length == 0) return Center(child: Text('${t('error')}: ${src.error}'));
        if (src.length == 0) {
          return src.hasMore
              ? const Center(child: CircularProgressIndicator())
              : Center(child: Text(t('no_results')));
        }
        return TimelineView(api: widget.api, source: src);
      },
    );
  }
}
