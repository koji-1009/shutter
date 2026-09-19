import 'package:flutter/material.dart';

/// A row of tags that does not wrap — overflows when the tags are long.
class TagRow extends StatelessWidget {
  const TagRow({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tag in tags)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(label: Text(tag)),
          ),
      ],
    );
  }
}
