/// What a shot run is doing, as it does it; each event's [message] is a
/// line for a log.
sealed class ShotProgress {
  const ShotProgress();

  /// One line describing the event, e.g. `rendered 03a31f8f5d859fec.0`.
  String get message;
}

/// The preview files are being read for their previews.
final class const ScanStarted(
  /// Project-relative POSIX paths of the preview files.
  final List<String> files,
) extends ShotProgress {
  @override
  String get message => 'scanning ${files.join(', ')}';
}

/// `flutter test` starts rendering every shot. [round] counts from 1; a
/// later round renders every shot again with the fonts the previous one
/// found missing.
final class const RenderStarted(final int round) extends ShotProgress {
  @override
  String get message =>
      round == 1 ? 'rendering' : 'rendering again with added fonts';
}

/// One shot finished rendering in [round]; whether it is `ok` or an
/// `error` is known when the run ends.
final class const ShotRendered(final int round, final String id)
    extends ShotProgress {
  @override
  String get message => 'rendered $id';
}

/// google_fonts files missing from the cache are being downloaded.
final class const FontsDownloading(
  /// File names of the fonts, e.g. `Lato-Regular.ttf`.
  final List<String> fonts,
) extends ShotProgress {
  @override
  String get message => 'downloading ${fonts.join(', ')}';
}
