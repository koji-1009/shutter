/// An expected failure with a user-facing message and a sysexits-aligned
/// exit code. [runApp] prints [message] to stderr and exits with
/// [exitCode]; anything else escaping a command is `EX_SOFTWARE` (70).
class ShutterException implements Exception {
  /// `EX_CONFIG` (78) — the project is not in a usable state.
  const ShutterException(this.message) : exitCode = 78;

  /// `EX_NOINPUT` (66) — a named run or file does not exist.
  ShutterException.noInput(this.message) : exitCode = 66;

  /// `EX_USAGE` (64) — the arguments are inconsistent.
  ShutterException.usage(this.message) : exitCode = 64;

  /// `EX_UNAVAILABLE` (69) — a required external tool (Flutter) is missing.
  ShutterException.unavailable(this.message) : exitCode = 69;

  final String message;

  final int exitCode;

  @override
  String toString() => 'shutter: $message';
}
