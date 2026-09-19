import 'dart:io';

/// Static interception point for the CLI's stdout / stderr — same shape
/// as `FlutterError.onError`. Production binaries leave the defaults
/// (`dart:io.stdout` / `dart:io.stderr`) in place; tests reassign the
/// fields to in-memory sinks so report payloads do not interleave with
/// the test reporter's own streams.
abstract final class ShutterIO {
  /// Sink for user-facing payload (reports, listings, docs).
  static IOSink stdoutSink = stdout;

  /// Sink for errors and warnings.
  static IOSink stderrSink = stderr;
}
