import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ⭐ PLACEHOLDER LINKS — replace these with your real social media URLs
// whenever you're ready. Nothing else in this file needs to change.
const List<SocialItem> socialItems = [
  SocialItem(
    icon: FontAwesomeIcons.facebook,
    label: "Facebook",
    url: "https://www.facebook.com/people/Super-Antequera-Radio-HD/100046497564932/#",
    color: Color(0xFF1877F2),
  ),
  SocialItem(
    icon: FontAwesomeIcons.instagram,
    label: "Instagram",
    url: "https://www.instagram.com/superantequeraradiohd",
    color: Color(0xFFE1306C),
  ),
  SocialItem(
    icon: FontAwesomeIcons.whatsapp,
    label: "WhatsApp",
    url: "https://wa.me/10000000000",
    color: Color(0xFF25D366),
  ),
  SocialItem(
    icon: FontAwesomeIcons.tiktok,
    label: "TikTok",
    url: "https://www.tiktok.com/@superantequera",
    color: Color(0xFFEE1D52),
  ),
  SocialItem(
    icon: FontAwesomeIcons.youtube,
    label: "YouTube",
    url: "https://www.youtube.com/channel/UCCWhf78miH_0XYD_u_G_Kmg",
    color: Color(0xFFFF0000),
  ),
];

class SocialItem {
  final FaIconData icon;
  final String label;
  final String url;
  final Color color;

  const SocialItem({
    required this.icon,
    required this.label,
    required this.url,
    required this.color,
  });
}

class SocialBanner extends StatefulWidget {
  const SocialBanner({super.key});

  @override
  State<SocialBanner> createState() => _SocialBannerState();
}

class _SocialBannerState extends State<SocialBanner> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;

      if (current >= maxScroll) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.jumpTo(current + 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Couldn't open $url: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Repeat the list a few times so the loop feels seamless — when it
    // jumps back to 0 there's still identical content just off-screen.
    final looped = [...socialItems, ...socialItems, ...socialItems];

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: looped.length,
        itemBuilder: (context, index) {
          final item = looped[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () => _open(item.url),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(item.icon, color: item.color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: GoogleFonts.montserrat(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
