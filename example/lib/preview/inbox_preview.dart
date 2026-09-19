import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../ui/inbox_screen.dart';

/// Light and dark variants of a phone-sized screen.
final class PhonePreview extends MultiPreview {
  const PhonePreview({required this.name});

  final String name;

  @override
  List<Preview> get previews => [
    Preview(name: '$name / light', size: const Size(390, 844)),
    Preview(
      name: '$name / dark',
      size: const Size(390, 844),
      brightness: Brightness.dark,
    ),
  ];
}

@PhonePreview(name: 'Inbox / empty')
Widget inboxEmpty() => const InboxScreen(state: InboxEmpty());

@PhonePreview(name: 'Inbox / loading')
Widget inboxLoading() => const InboxScreen(state: InboxLoading());

@PhonePreview(name: 'Inbox / error')
Widget inboxError() =>
    const InboxScreen(state: InboxFailed('Could not reach the server'));

@PhonePreview(name: 'Inbox / loaded')
Widget inboxLoaded() => const InboxScreen(
  state: InboxLoaded(['Welcome to shutter', 'Your weekly summary']),
);
