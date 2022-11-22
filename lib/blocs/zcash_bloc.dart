import 'dart:async';

import 'package:http/http.dart';
import 'package:komodo_dex/blocs/coins_bloc.dart';
import 'package:komodo_dex/model/balance.dart';
import 'package:komodo_dex/model/coin.dart';
import 'package:komodo_dex/model/coin_balance.dart';
import 'package:komodo_dex/services/db/database.dart';
import 'package:komodo_dex/services/job_service.dart';
import 'package:komodo_dex/services/mm.dart';
import 'package:komodo_dex/services/mm_service.dart';
import 'package:komodo_dex/utils/log.dart';
import 'package:komodo_dex/utils/utils.dart';
import 'package:komodo_dex/widgets/bloc_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ZCashBloc implements BlocBase {
  // Streams to zcash params download progress
  final StreamController<Map<int, ZTask>> _zcashProgressController =
      StreamController<Map<int, ZTask>>.broadcast();

  List<Coin> coinsToActivate = [];
  Map<int, ZTask> tasksToCheck = {};

  Sink<Map<int, ZTask>> get _inZcashProgress => _zcashProgressController.sink;
  Stream<Map<int, ZTask>> get outZcashProgress =>
      _zcashProgressController.stream;

  @override
  void dispose() {
    _zcashProgressController.close();
  }

  List<Coin> removeZcashCoins(List<Coin> coins) {
    coinsToActivate =
        coins.where((element) => element?.protocol?.type == 'ZHTLC').toList();
    if (coinsToActivate.isNotEmpty) {
      // remove zcash-coins from the main coin list if it exists
      coins.removeWhere((coin) => coinsToActivate.contains(coin));
      downloadZParams();
      return coins;
    } else {
      return coins;
    }
  }

  Future autoEnableZcashCoins() async {
    final List<Map<String, dynamic>> batch = [];

    final dir = await getApplicationDocumentsDirectory();
    String folder = Platform.isIOS ? '/ZcashParams/' : '/.zcash-params/';
    for (Coin coin in coinsToActivate) {
      final electrum = {
        'userpass': mmSe.userpass,
        'method': 'task::enable_z_coin::init',
        'mmrpc': '2.0',
        'params': {
          'ticker': coin.abbr,
          'activation_params': {
            'mode': {
              'rpc': 'Light',
              'rpc_data': {
                'electrum_servers': Coin.getServerList(coin.serverList),
                'light_wallet_d_servers': coin.lightWalletDServers
              }
            },
            'zcash_params_path': dir.path + folder
          },
        }
      };
      batch.add(electrum);
    }

    final replies = await MM.batch(batch);
    if (replies.length != coinsToActivate.length) {
      throw Exception(
          'Unexpected number of replies: ${replies.length} != ${coinsToActivate.length}');
    }

    for (int i = 0; i < replies.length; i++) {
      final reply = replies[i];
      int id = reply['result']['task_id'];
      tasksToCheck[id] = ZTask(abbr: coinsToActivate[i].abbr, progress: 0);
      jobService.suspend('checkPresentZcashEnabling');
      startStatusChecking();
    }
    _inZcashProgress.add(tasksToCheck);
  }

  void startStatusChecking() {
    jobService.install('checkPresentZcashEnabling', 5, (j) async {
      if (tasksToCheck.isEmpty) {
        jobService.suspend('checkPresentZcashEnabling');
        return;
      }
      if (!mmSe.running) return;
      for (var task in tasksToCheck.keys) {
        dynamic res = await MM.getZcashActivationStatus({
          'userpass': mmSe.userpass,
          'method': 'task::enable_z_coin::status',
          'mmrpc': '2.0',
          'params': {'task_id': task},
          'id': task,
        });

        _zhtlcActivationProgress(res, task);
      }
    });
  }

  void _zhtlcActivationProgress(
      Map<String, dynamic> activationData, int id) async {
    int _progress = 100;
    String _messageDetails = '';
    if (!activationData.containsKey('result')) return;
    String abbr = tasksToCheck[id].abbr;
    String status = activationData['result']['status'];
    dynamic details = activationData['result']['details'];

    int blockOffset = 0;
    if (abbr == 'ARRR') blockOffset = 1900000;

    // use range from checkpoint block to present
    if (status == 'Ok') {
      if (details.containsKey('error')) {
        Log('zcash_bloc:273', 'Error activating $abbr: ${details['error']}');
      } else {
        Coin coin = coinsBloc.getKnownCoinByAbbr(abbr);

        await Db.coinActive(coin);
        final bal = Balance(
            address: details['wallet_balance']['address'],
            balance: deci(details['wallet_balance']['balance']['spendable']),
            lockedBySwaps:
                deci(details['wallet_balance']['balance']['unspendable']),
            coin: details['ticker']);
        bal.camouflageIfNeeded();
        final cb = CoinBalance(coin, bal);
        // Before actual coin activation, coinBalance can store
        // coins data (including balanceUSD) loaded from wallet snapshot,
        // created during previous session (#898)
        final double preSavedUsdBalance =
            coinsBloc.getBalanceByAbbr(abbr)?.balanceUSD;
        cb.balanceUSD = preSavedUsdBalance ?? 0;
        coinsBloc.updateOneCoin(cb);

        await coinsBloc.syncCoinsStateWithApi();
        coinsBloc.currentCoinActivate(null);
      }
      tasksToCheck.remove(id);
    } else if (status == 'InProgress') {
      if (details == 'ActivatingCoin') {
        _progress = 5;
        _messageDetails = 'Activating $abbr';
      } else if (details == 'RequestingBalance') {
        _progress = 98;
        _messageDetails = 'Requesting $abbr balance';
      } else if (details.containsKey('UpdatingBlocksCache')) {
        int n = details['UpdatingBlocksCache']['current_scanned_block'] -
            blockOffset;
        int d = details['UpdatingBlocksCache']['latest_block'] - blockOffset;
        _progress = 5 + (n / d * 15).toInt();
        _messageDetails = 'Updating $abbr blocks cache';
      } else if (details.containsKey('BuildingWalletDb')) {
        int n =
            details['BuildingWalletDb']['current_scanned_block'] - blockOffset;
        int d = details['BuildingWalletDb']['latest_block'] - blockOffset;
        _progress = 20 + (n / d * 80).toInt();
        _messageDetails = 'Building $abbr wallet database';
      } else {
        _progress = 5;
        _messageDetails = 'Activating $abbr';
      }
    } else {
      tasksToCheck.remove(id);
      Log('zcash_bloc:273', 'Error activating $abbr: unexpected error');
    }
    if (tasksToCheck[id] != null) {
      tasksToCheck[id].progress = _progress;
      tasksToCheck[id].message = _messageDetails;
    }
    _inZcashProgress.add(tasksToCheck);
  }

  Future<void> downloadZParams() async {
    final dir = await getApplicationDocumentsDirectory();
    String folder = Platform.isIOS ? '/ZcashParams/' : '/.zcash-params/';
    Directory zDir = Directory(dir.path + folder);
    if (zDir.existsSync() && mmSe.dirStatSync(zDir.path, endsWith: '') > 50) {
      autoEnableZcashCoins();
      return;
    } else if (!zDir.existsSync()) {
      zDir.createSync();
    }

    final params = [
      'https://z.cash/downloads/sapling-spend.params',
      'https://z.cash/downloads/sapling-output.params',
    ];

    int _received = 0;
    int _totalDownloadSize = 0;
    for (var param in params) {
      final List<int> _bytes = [];

      StreamedResponse _response;
      _response = await Client().send(Request('GET', Uri.parse(param)));
      _totalDownloadSize += _response.contentLength ?? 0;
      tasksToCheck[20] =
          ZTask(message: 'Downloading Zcash params...', progress: 0);
      _inZcashProgress.add(tasksToCheck);
      _response.stream.listen((value) {
        _bytes.addAll(value);
        _received += value.length;
        tasksToCheck[20].progress =
            ((_received / _totalDownloadSize) * 100).toInt();
        _inZcashProgress.add(tasksToCheck);
      }).onDone(() async {
        final file = File(zDir.path + param.split('/').last);
        if (!file.existsSync()) await file.create();
        await file.writeAsBytes(_bytes);
        _inZcashProgress.add(tasksToCheck);
        if (_received / _totalDownloadSize == 1) {
          tasksToCheck.remove(20);
          autoEnableZcashCoins();
        }
      });
    }
  }
}

class ZTask {
  String abbr;
  String message;
  int progress;

  ZTask({this.abbr, this.message, this.progress});
}

ZCashBloc zcashBloc = ZCashBloc();
