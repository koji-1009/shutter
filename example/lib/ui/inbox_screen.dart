import 'package:flutter/material.dart';

sealed class InboxState {
  const InboxState();
}

class InboxEmpty extends InboxState {
  const InboxEmpty();
}

class InboxLoading extends InboxState {
  const InboxLoading();
}

class InboxFailed extends InboxState {
  const InboxFailed(this.message);

  final String message;
}

class InboxLoaded extends InboxState {
  const InboxLoaded(this.messages);

  final List<String> messages;
}

/// A screen whose state is passed in, so every state can be previewed.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.state});

  final InboxState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: switch (state) {
        InboxEmpty() => const Center(child: Text('No messages yet')),
        InboxLoading() => const Center(child: CircularProgressIndicator()),
        InboxFailed(:final message) => Center(
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        InboxLoaded(:final messages) => ListView(
          children: [
            for (final message in messages) ListTile(title: Text(message)),
          ],
        ),
      },
    );
  }
}
