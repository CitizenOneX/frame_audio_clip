import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:frame_audio_clip/audio_data_response.dart';
import 'package:logging/logging.dart';

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
  }

  @override
  void dispose() async {
    await audioClipStreamSubs?.cancel();
    super.dispose();
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // attach a handler to listen for the audio clip
      await audioClipStreamSubs?.cancel();
      audioClipStreamSubs = audioDataResponse(frame!.dataResponse).listen((audioData) {
        _log.info('Clip length: ${audioData.length} bytes');
      });

      // tell Frame to start streaming audio
      await frame!.sendMessage(TxCode(msgCode: 0x30));

      // wait a while
      await Future.delayed(const Duration(seconds: 1));

      // tell Frame to stop
      await frame!.sendMessage(TxCode(msgCode: 0x31));

      // TODO should really block until the audio data has come back so the UI doesn't allow us to kick it off again

      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    // TODO any logic while canceling?

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Simple Frame App Template',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Simple Frame App Template'),
              actions: [getBatteryWidget()]),
          body: const Padding(
            padding: EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Spacer(),
              ],
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.file_open), const Icon(Icons.close)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
