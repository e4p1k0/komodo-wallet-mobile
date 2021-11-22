import 'package:flutter/material.dart';
import 'package:komodo_dex/localizations.dart';
import 'package:komodo_dex/model/feed_provider.dart';
import 'package:komodo_dex/screens/feed/news/build_news_item.dart';
import 'package:provider/provider.dart';

class NewsTab extends StatefulWidget {
  @override
  _NewsTabState createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  FeedProvider _feedProvider;
  List<NewsItem> _news;

  @override
  Widget build(BuildContext context) {
    _feedProvider = Provider.of<FeedProvider>(context);
    _news = _feedProvider.getNews();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_feedProvider.hasNewItems) {
        _feedProvider.hasNewItems = false;
      }
    });

    if (_news == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_news.isEmpty) {
      return Center(
          child: Text(
        AppLocalizations.of(context).feedNotFound,
        style: const TextStyle(fontSize: 13),
      ));
    }

    Widget _buildUpdateIndicator() {
      return _feedProvider.isNewsFetching
          ? const SizedBox(
              height: 1,
              child: LinearProgressIndicator(),
            )
          : Container(height: 1);
    }

    return Column(
      children: <Widget>[
        _buildUpdateIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final String updateResponse = await _feedProvider.updateNews();
              String message;
              if (updateResponse == 'ok') {
                message = AppLocalizations.of(context).feedUpdated;
              } else {
                message = updateResponse;
              }

              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).disabledColor),
                ),
                backgroundColor: Theme.of(context).backgroundColor,
                duration: const Duration(seconds: 1),
                action: SnackBarAction(
                  textColor: Theme.of(context).colorScheme.secondary,
                  label: AppLocalizations.of(context).snackbarDismiss,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ));
            },
            child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: _news.length,
                itemBuilder: (BuildContext context, int i) {
                  return Column(
                    children: <Widget>[
                      BuildNewsItem(_news[i]),
                    ],
                  );
                }),
          ),
        ),
      ],
    );
  }
}
