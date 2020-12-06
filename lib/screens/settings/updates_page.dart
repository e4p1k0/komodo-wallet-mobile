import 'dart:io';

import 'package:flutter/material.dart';
import 'package:komodo_dex/localizations.dart';
import 'package:komodo_dex/model/updates_provider.dart';
import 'package:komodo_dex/utils/utils.dart';
import 'package:provider/provider.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({this.refresh = false, this.onSkip});

  final bool refresh;
  final Function onSkip;

  @override
  _UpdatesPageState createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  UpdatesProvider updatesProvider;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.refresh) updatesProvider.check();
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    updatesProvider = Provider.of<UpdatesProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).backgroundColor,
      resizeToAvoidBottomPadding: false,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).updatesTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          updatesProvider.check();
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            Container(
              height: MediaQuery.of(context).size.height / 3,
              child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Image.asset('assets/logo_kmd.png'),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context).updatesCurrentVersion(
                          updatesProvider.currentVersion)),
                      const SizedBox(height: 4),
                      updatesProvider.isFetching
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                const SizedBox(width: 6),
                                Text(AppLocalizations.of(context)
                                    .updatesChecking)
                              ],
                            )
                          : updatesProvider.status == UpdateStatus.upToDate
                              ? Text(
                                  AppLocalizations.of(context).updatesUpToDate)
                              : Text(
                                  AppLocalizations.of(context)
                                          .updatesAvailable +
                                      '${updatesProvider.newVersion == null ? '' : ': ${updatesProvider.newVersion}'}',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                )
                    ],
                  )),
            ),
            if (updatesProvider.message != null)
              Container(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Divider(
                      color: Theme.of(context).hintColor,
                      height: 60,
                    ),
                    Text(updatesProvider.message),
                  ],
                ),
              ),
            if (updatesProvider.status != UpdateStatus.upToDate &&
                !updatesProvider.isFetching)
              Container(
                height: MediaQuery.of(context).size.height / 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    RaisedButton(
                      color: Theme.of(context).dialogBackgroundColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: Theme.of(context).textTheme.caption.color),
                        borderRadius: BorderRadius.circular(30.0),
                      ),
                      onPressed: () {
                        Platform.isIOS
                            ? launchURL(
                                'https://testflight.apple.com/join/c2mOLEoC')
                            : launchURL(
                                'https://play.google.com/store/apps/details?id=com.komodoplatform.atomicdex');
                      },
                      child: Text(AppLocalizations.of(context).updatesUpdate),
                    ),
                    if (updatesProvider.status == UpdateStatus.available ||
                        updatesProvider.status == UpdateStatus.recommended) ...[
                      const SizedBox(width: 12),
                      RaisedButton(
                        color: Theme.of(context).dialogBackgroundColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                              color: Theme.of(context).textTheme.caption.color),
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        onPressed: () {
                          if (widget.onSkip != null) widget.onSkip();
                        },
                        child: Text(AppLocalizations.of(context).updatesSkip),
                      )
                    ]
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }
}
