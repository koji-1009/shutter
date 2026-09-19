import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A card whose fonts come from google_fonts, resolved while it builds.
class GreetingCard extends StatelessWidget {
  const GreetingCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.lobster(fontSize: 28)),
            const SizedBox(height: 8),
            Text(body, style: GoogleFonts.notoSansJp(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
