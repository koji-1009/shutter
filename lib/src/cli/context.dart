import 'dart:io';

import '../engine/engine.dart';
import '../engine/flutter_test_engine.dart';
import '../project/flutter_sdk.dart';
import '../project/project.dart';

/// Builds the engine for a located SDK.
typedef EngineFactory = Engine Function(FlutterSdk sdk);

/// Everything a command reads from the outside world. Production uses
/// the defaults; tests substitute a directory, a clock, an environment,
/// and a fake engine.
class ShutterContext {
  ShutterContext({
    String? workingDirectory,
    DateTime Function()? clock,
    Map<String, String>? environment,
    EngineFactory? engineFactory,
  }) : workingDirectory = workingDirectory ?? Directory.current.path,
       clock = clock ?? DateTime.now,
       environment = environment ?? Platform.environment,
       engineFactory = engineFactory ?? _flutterTestEngine;

  final String workingDirectory;
  final DateTime Function() clock;
  final Map<String, String> environment;
  final EngineFactory engineFactory;

  Project project() => Project.find(workingDirectory);

  FlutterSdk sdk() => FlutterSdk.require(environment: environment);
}

Engine _flutterTestEngine(FlutterSdk sdk) => FlutterTestEngine(sdk: sdk);
