import 'dart:math';

import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:komodo_dex/model/order.dart';
import 'package:komodo_dex/model/swap.dart';
import 'package:komodo_dex/utils/log.dart';

MusicService musicService = MusicService();

enum MusicMode {
  /// Trying to match with an existing order.
  TAKER,

  /// Having orders.
  MAKER,

  /// There are active swaps.
  ACTIVE,

  /// There was a failed swap recently.
  FAILED,

  /// There was a finished swap recently.
  APPLAUSE,

  /// No active orders or swaps, we can stay silent
  /// (and allow the application to be suspended, saving battery life).
  SILENT
}

class MusicService {
  MusicService() {
    _audioPlayer.onPlayerCompletion.listen((_) {
      // Happens when a music (mp3) file is finished, multiple times when we're using a `loop`.
      //Log.println('music_service:37', 'onPlayerCompletion');
    });
    _audioPlayer.onPlayerError.listen((String ev) {
      Log.println('music_service:40', 'onPlayerError: ' + ev);
    });
  }

  /// Initially `null` (unknown) in order to trigger `recommendsPeriodicUpdates`.
  MusicMode musicMode;

  /// Whether the volume is currently up.
  bool _on = true;

  /// Maps a mode to the path of a custom sound configured by user.
  final Map<MusicMode, String> _soundPaths = {};

  /// The path of the sound currently played.
  String _soundPath;

  static final AudioPlayer _audioPlayer =
      AudioPlayer(mode: PlayerMode.MEDIA_PLAYER);
  static final AudioCache _player =
      AudioCache(prefix: 'audio/', fixedPlayer: _audioPlayer);

  /// Pick the current music mode based on the list of all the orders and SWAPs.
  MusicMode pickMode(
      List<Order> orders, List<Swap> swaps, List<Swap> allSwaps) {
    // ignore: always_specify_types
    final Set<String> active = {};
    for (final Swap swap in swaps) {
      // Active swaps.
      final String uuid = swap.result.uuid;
      active.add(uuid);
      final String shortId = uuid.substring(0, 4);
      Log.println('music_service:71',
          'pickMode] swap $shortId status: ${swap.status}, MusicMode.ACTIVE');
      return MusicMode.ACTIVE;
    }

    for (final Swap swap in allSwaps) {
      final String uuid = swap.result.uuid;
      if (active.contains(uuid)) {
        // Already seen this swap in the list of active swaps.
        continue;
      }
      final String shortId = uuid.substring(0, 4);
      if (musicMode == MusicMode.ACTIVE) {
        if (swap.status == Status.SWAP_FAILED ||
            swap.status == Status.TIME_OUT) {
          Log.println('music_service:86',
              'pickMode] failed swap $shortId, MusicMode.FAILED');
          return MusicMode.FAILED;
        } else if (swap.status == Status.SWAP_SUCCESSFUL) {
          Log.println('music_service:90',
              'pickMode] finished swap $shortId, MusicMode.APPLAUSE');
          return MusicMode.APPLAUSE;
        }
      }
    }

    for (final Order order in orders) {
      final String shortId = order.uuid.substring(0, 4);
      if (order.orderType == OrderType.TAKER) {
        Log.println('music_service:100',
            'pickMode] taker order $shortId, MusicMode.TAKER');
        return MusicMode.TAKER;
      } else if (order.orderType == OrderType.MAKER) {
        Log.println('music_service:104',
            'pickMode] maker order $shortId, MusicMode.MAKER');
        return MusicMode.MAKER;
      }
    }

    Log.println('music_service:110',
        'pickMode] no active orders or swaps, MusicMode.SILENT');
    return MusicMode.SILENT;
  }

  void setSoundPath(MusicMode mode, String path) {
    _soundPaths[mode] = path;
    Log.println('music_service:117', 'setSoundPath $mode, $path');
  }

  // First batch of audio files was gathered by the various members of Komodo team
  // and had funny names testimony to the gay variety of places it came from:
  // 15427__lg__fax, Coin_Drop-Willem_Hunt-569197907, 162196__rickmk2__coin-rustle,
  // 362272__zabuhailo__street-musician-money, 376196__euphrosyyn__futuristic-robotic-voice-sentences,
  // 213901__garzul__robotic-arp-sequence, Cash-Register-Cha-Ching-SoundBible.com-184076484,
  // poker-chips-daniel_simon
  // We did a pair programming session on classifying that music
  // and it was a bit of a surprise that every one of them has fallen into a place.
  //
  // If we are to expand the collection of audio tracks
  // then the idea is to have some default tracks in the application bundle
  // (just to minimally cover all the modes)
  // and download the extra tracks on demand from an external server
  // in order to keep the application bundle (and Git repository) small.

  void play(List<Order> orders, List<Swap> swaps, List<Swap> allSwaps) {
    // ^ Triggered by page transitions and certain log events (via `onLogsmm2`),
    //   but for reliability we should also add a periodic update independent from MM logs.
    final MusicMode newMode = pickMode(orders, swaps, allSwaps);
    bool changes = false;

    if (newMode != musicMode) {
      changes = true;
      Log.println('music_service:143',
          'play] mode changed from $musicMode to $newMode');
    }

    final String customPath = _soundPaths[newMode];

    () async {
      try {
        // This is what the audio player does:
        await rootBundle.load('assets/audio/$customPath');
        // ^^ hence we'll need to copy the file to the assets for it to be loadable.
        // I wonder if we should simply overwrite our asset audio file.
      } catch (ex) {
        Log.println('music_service:156', 'rootBundle.load exception: $ex');
      }
    }();

    Log.println('music_service:160', 'custom sound path: $customPath');
    if (customPath != null && customPath != _soundPath) changes = true;

    if (!changes) return;

    final Random rng = Random();

    final String defaultPath = newMode == MusicMode.TAKER
        ? (rng.nextBool() ? 'taker1.mp3' : 'taker2.mp3')
        : newMode == MusicMode.MAKER
            ? 'maker.mp3'
            : newMode == MusicMode.ACTIVE
                ? 'active.mp3'
                : newMode == MusicMode.FAILED
                    ? (rng.nextBool() ? 'failed1.mp3' : 'failed2.mp3')
                    : newMode == MusicMode.APPLAUSE
                        ? 'applause.mp3'
                        : newMode == MusicMode.SILENT ? 'lastSound.mp3' : null;

    final String path = customPath ?? defaultPath;
    Log.println('music_service:180', 'path: $path');

    _soundPath = path;

    if (newMode == MusicMode.TAKER) {
      _player.loop(path, volume: volume());
    } else if (newMode == MusicMode.MAKER) {
      _player.loop(path, volume: volume());
    } else if (newMode == MusicMode.ACTIVE) {
      _player.loop(path, volume: volume());
    } else if (newMode == MusicMode.FAILED) {
      _audioPlayer.setReleaseMode(ReleaseMode.RELEASE);
      _player.play(path, volume: volume());
    } else if (newMode == MusicMode.APPLAUSE) {
      _audioPlayer.setReleaseMode(ReleaseMode.RELEASE);
      _player.play(path, volume: volume());
    } else if (newMode == MusicMode.SILENT) {
      _audioPlayer.setReleaseMode(ReleaseMode.RELEASE);
      _player.play(path, volume: volume());
    } else {
      Log.println('music_service:200', 'Unexpected music mode: $newMode');
      _audioPlayer.stop();
    }

    musicMode = newMode;
  }

  /// True when we want to periodically update the orders and swaps.
  ///
  /// As of now the lists of orders and swaps are not a part of a separate model
  /// but are instead embedded into the UI orders and swap history blocks.
  /// This results in unreliable updates of those list
  /// as the said updates either aren't triggered when these blocks are not visible
  /// or triggered belatedly and out of order, during UI transitions and such.
  ///
  /// Hence when the music is playing we want to also trigger an update of these list with a separate timer.
  ///
  /// We also want an update whenever the `musicMode` is unknown,
  /// which happens after the application restarts.
  bool recommendsPeriodicUpdates() {
    return musicMode != MusicMode.SILENT;
  }

  /// Current audio player volume, from 0 to 1, based on the `on` switch.
  double volume() {
    // AG: We don't want the volume to be *too* low
    // for otherwise reviewers might think that we're using the infamous silent audio trick.
    return _on ? 1 : 0.1;
  }

  /// True if the music volume is currently up.
  bool on() {
    return _on;
  }

  /// Tune the volume down or back up.
  void flip() {
    _on = !_on;
    _audioPlayer.setVolume(volume());
  }
}
