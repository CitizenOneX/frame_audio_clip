import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:raw_sound/raw_sound_player.dart';
import 'package:simple_frame_app/rx/audio.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/code.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  StreamSubscription<Uint8List>? audioClipStreamSubs;
  final List<Uint8List> _rawAudioClips = [];
  final _player = RawSoundPlayer();
  int? _playingIndex;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    // use a small buffer to allow short clips to be played - raw_sound won't play clips smaller than bufferSize bytes
    _player.initialize(bufferSize: 4096, nChannels: 1, sampleRate: 8000, pcmType: RawSoundPCMType.PCMI16).then((value) {
      setState(() {
        // Trigger rebuild to update UI
      });
    });
  }

  @override
  void dispose() async {
    await audioClipStreamSubs?.cancel();
    await _player.release();
    super.dispose();
  }

  /// Start recording audio on Frame
  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // attach a handler to listen for the audio clip
      await audioClipStreamSubs?.cancel();
      audioClipStreamSubs = RxAudio().attach(frame!.dataResponse).listen((audioData) {
        _log.info('Clip length: ${audioData.length} bytes');
        setState(() {
          _rawAudioClips.add(audioData);
          currentState = ApplicationState.ready;
        });
      });

      // tell Frame to start streaming audio
      await frame!.sendMessage(TxCode(msgCode: 0x30));

    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  /// Stop recording audio on Frame
  @override
  Future<void> cancel() async {

    // in canceling state, the user can't click other buttons to start/stop
    // and the state will return to ready when the audio data is all received
    setState(() {
      currentState = ApplicationState.canceling;
    });

    // tell Frame to stop streaming audio
    await frame!.sendMessage(TxCode(msgCode: 0x31));
  }

  /// Play the audio from the selected recording
  Future<void> _playAudio(Uint8List audioBytes, int index) async {
    if (!_player.isPlaying) {
      await _player.play();
      setState(() {
        _playingIndex = index;
      });
    }

    if (_player.isPlaying) {
      // TODO skip the pop at the beginning of the recording? or not?
      //await _player.feed(Uint8List.fromList(audioBytes.skip(2700).toList()));
      await _player.feed(Uint8List.fromList(audioBytes));
    }

    // no obvious callback from raw_sound when playback finishes, so since we know
    // how long the clip is, we can wait then update the UI (show play button instead of stop)
    // but be aware that the user might have stopped playback early, so bail out
    int clipDurationMs = (audioBytes.length/16.0).toInt();
    int waited = 0;

    while (_player.isPlaying && waited < clipDurationMs) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    await _stopAudio();
  }

  /// Cancel the playing of the selected recording
  Future<void> _stopAudio() async {
    if (_player.isPlaying) {
      await _player.stop();
      setState(() {
        _playingIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Frame Audio Recorder',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Frame Audio Recorder'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ListView.builder(
              itemCount: _rawAudioClips.length,
              itemBuilder: (context, index) {
                return Card(
                  child: ListTile(
                    title: Text('Audio Clip ${index + 1} (${(_rawAudioClips[index].length/2/8000.0).toStringAsFixed(2)}s)'),
                    trailing: _playingIndex == index ?
                      IconButton(
                        icon: const Icon(Icons.stop),
                        onPressed: () {
                          _stopAudio();
                        },
                       ) :
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () {
                          _playAudio(_rawAudioClips[index], index);
                        },
                      ),
                  ),
                );
              },
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.mic), const Icon(Icons.stop)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
