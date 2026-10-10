import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../widgets/timeline_view.dart';

/// Results for the top search bar / "Search options" filter.
class SearchResults extends StatefulWidget {
  final ImmichApi api;
  final SearchFilter filter;

  const SearchResults({super.key, required this.api, required this.filter});

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
    if (!identical(old.filter, widget.filter)) _start();
  }

  @override
  void dispose() {
    _source?.dispose();
    super.dispose();
  }

  void _start() {
    final f = widget.filter.copy();
    final old = _source;
    if (f.isEmpty) {
      _source = null;
    } else {
      final api = widget.api;
      _source = SearchSource((page) => api.search(f, page: page))..loadMore();
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
