import 'value.dart';

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

  @override
  bool operator ==(Object other) =>
      other is ScanStarted && sameElements(other.files, files);

  @override
  int get hashCode => Object.hashAll(files);

  @override
  String toString() => describe('ScanStarted', {'files': files});
}

/// `flutter test` starts rendering every shot. [round] counts from 1; a
/// later round renders every shot again with the fonts the previous one
/// found missing.
final class const RenderStarted(final int round) extends ShotProgress {
  @override
  String get message =>
      round == 1 ? 'rendering' : 'rendering again with added fonts';

  @override
  bool operator ==(Object other) =>
      other is RenderStarted && other.round == round;

  @override
  int get hashCode => Object.hash(RenderStarted, round);

  @override
  String toString() => describe('RenderStarted', {'round': round});
}

/// One shot finished rendering in [round]; whether it is `ok` or an
/// `error` is known when the run ends.
final class const ShotRendered(final int round, final String id)
    extends ShotProgress {
  @override
  String get message => 'rendered $id';

  @override
  bool operator ==(Object other) =>
      other is ShotRendered && other.round == round && other.id == id;

  @override
  int get hashCode => Object.hash(round, id);

  @override
  String toString() => describe('ShotRendered', {'round': round, 'id': id});
}

/// google_fonts files missing from the cache are being downloaded.
final class const FontsDownloading(
  /// File names of the fonts, e.g. `Lato-Regular.ttf`.
  final List<String> fonts,
) extends ShotProgress {
  @override
  String get message => 'downloading ${fonts.join(', ')}';

  @override
  bool operator ==(Object other) =>
      other is FontsDownloading && sameElements(other.fonts, fonts);

  @override
  int get hashCode => Object.hashAll(fonts);

  @override
  String toString() => describe('FontsDownloading', {'fonts': fonts});
}
