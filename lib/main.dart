import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'chat_screen.dart';
import 'social_banner.dart';

const _streamUrl = "http://us2.internet-radio.com:8387/live";

// ⭐ Wraps the media_kit Player so Android treats playback as a real
// background media session: foreground service + notification + lock
// screen controls. This is what keeps audio alive when the screen locks.
class RadioAudioHandler extends BaseAudioHandler with SeekHandler {
  final Player player = Player();

  RadioAudioHandler() {
    mediaItem.add(const MediaItem(
      id: _streamUrl,
      album: "La Señal de Oaxaca",
      title: "Super Antequera Radio HD",
      artist: "Loading…",
    ));

    player.stream.playing.listen((isPlaying) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.play, MediaAction.pause},
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.ready,
        playing: isPlaying,
      ));
    });
  }

  Future<void> initStream() async {
    try {
      await player.open(
        Media(
          _streamUrl,
          httpHeaders: {
            "User-Agent": "Mozilla/5.0",
            "Icy-MetaData": "1",
            "Accept": "audio/mpeg",
          },
        ),
        play: true,
      );
    } catch (e) {
      debugPrint("Stream load error: $e");
    }
  }

  // Called from the ICY metadata listener so the lock-screen / notification
  // media info stays in sync with what's showing in the app.
  void updateNowPlaying({String? songTitle, String? artist, String? artUrl}) {
    final current = mediaItem.value;
    mediaItem.add(
      (current ?? const MediaItem(id: _streamUrl, title: "Super Antequera Radio HD"))
          .copyWith(
        title: (songTitle != null && songTitle.isNotEmpty)
            ? songTitle
            : "Super Antequera Radio HD",
        artist: artist,
        artUri: (artUrl != null) ? Uri.tryParse(artUrl) : null,
      ),
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    await player.pause();
    await super.stop();
  }
}

late final RadioAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Firebase.initializeApp();

  audioHandler = await AudioService.init(
    builder: () => RadioAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.superantequeraradio.app.channel.audio',
      androidNotificationChannelName: 'Super Antequera Radio',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(const RadioApp());
}

class RadioApp extends StatefulWidget {
  const RadioApp({super.key});

  @override
  State<RadioApp> createState() => _RadioAppState();
}

class _RadioAppState extends State<RadioApp> with TickerProviderStateMixin {
  Player get player => audioHandler.player;

  String? artist;
  String? title;
  String? artworkUrl;
  bool playing = false;
  double volume = 80;

  late AnimationController vinylController;
  late AnimationController liveController;
  late AnimationController eqController;
  late AnimationController logoSpinController;
  late Animation<double> livePulse;

  // ⭐ Persistent equalizer state — these are now resized dynamically to
  // match however many bars actually fit on screen (see buildAudioEqualizer).
  // Starting with a reasonable default; will be resized on first layout.
  List<double> previousHeights = List.filled(40, 0);
  List<double> peakHeights = List.filled(40, 0);
  List<double> peakOpacity = List.filled(40, 1.0);
  List<double> phases =
  List.generate(40, (i) => math.Random().nextDouble() * 2 * math.pi);
  // ⭐ Per-bar random factor (0.55–1.0) so bars vary organically instead of
  // repeating in an obvious "every 5th bar" cycle.
  List<double> barFactors =
  List.generate(40, (i) => 0.55 + math.Random().nextDouble() * 0.45);

  @override
  void initState() {
    super.initState();
    audioHandler.initStream();

    vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    logoSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    liveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    livePulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: liveController, curve: Curves.easeInOut),
    );

    eqController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    player.stream.playing.listen((isPlaying) {
      setState(() => playing = isPlaying);
      if (isPlaying) {
        vinylController.repeat();
      } else {
        vinylController.stop();
      }
    });

    player.stream.volume.listen((v) {
      setState(() => volume = v);
    });

    final native = player.platform;
    if (native is NativePlayer) {
      native.observeProperty('metadata/by-key/icy-title', (value) async {
        if (value.isEmpty) return;

        final parts = value.split(" - ");
        final newArtist = parts.length > 1 ? parts[0] : "";
        final newTitle = parts.length > 1 ? parts[1] : value;

        setState(() {
          artist = newArtist;
          title = newTitle;
        });

        final url = await fetchArtwork(newArtist, newTitle);
        setState(() {
          artworkUrl = url;
        });

        audioHandler.updateNowPlaying(
          songTitle: newTitle,
          artist: newArtist,
          artUrl: url,
        );
      });
    }

    // Mic capture is no longer used — the equalizer now runs on a
    // decorative animation instead, so no microphone permission is
    // requested at all.
  }

  Future<String?> fetchArtwork(String artist, String title) async {
    if (artist.isEmpty && title.isEmpty) return null;

    final query = Uri.encodeComponent("$artist $title");
    final url = Uri.parse(
      "https://itunes.apple.com/search?term=$query&entity=song&limit=1",
    );

    try {
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      final jsonString = await response.transform(const Utf8Decoder()).join();
      final data = jsonDecode(jsonString);

      if (data["resultCount"] > 0) {
        final thumbnailUrl = data["results"][0]["artworkUrl100"] as String;
        // iTunes serves higher-res art at the same path if you swap the
        // "100x100" size segment for a bigger one — avoids stretching a
        // tiny 100px thumbnail up to fill the vinyl.
        return thumbnailUrl.replaceFirst("100x100bb", "600x600bb");
      }
    } catch (e) {
      debugPrint("Artwork fetch error: $e");
    }

    return null;
  }

  @override
  void dispose() {
    vinylController.dispose();
    liveController.dispose();
    eqController.dispose();
    logoSpinController.dispose();
    // Note: player is NOT disposed here — it's owned by the global
    // audioHandler / background audio service and should keep running.
    super.dispose();
  }

  // ⭐ LED segment color: blue (bottom) → cyan → green → yellow → red (top),
  // matching a classic hardware spectrum-analyzer look.
  Color segmentColor(int indexFromBottom, int totalSegments) {
    final t = totalSegments <= 1
        ? 0.0
        : indexFromBottom / (totalSegments - 1);
    final hue = 240 - (240 * t); // 240=blue ... 0=red
    return HSVColor.fromAHSV(1.0, hue.clamp(0, 240), 0.85, 1.0).toColor();
  }

  Widget frostedPanel({required Widget child, double padding = 24}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  // ⭐ Bars always run on a decorative animated "fake" motion — not driven
  // by mic input or actual stream audio. This avoids the mic-vs-headphones
  // problem entirely and looks the same regardless of output device.
  Widget buildAudioEqualizer() {
    const barWidth = 8.0;
    const barHorizontalMargin = 2.0; // applied on each side => 4px/bar total
    const slotWidth = barWidth + barHorizontalMargin * 2;
    const segmentHeight = 4.0;
    const segmentGap = 2.0;
    const segmentPitch = segmentHeight + segmentGap;

    return LayoutBuilder(
      builder: (context, constraints) {
        // How many bars actually fit in the available width?
        final maxBars = constraints.maxWidth.isFinite
            ? (constraints.maxWidth / slotWidth).floor()
            : 40;
        final barCount = maxBars.clamp(4, 40);

        // How many LED segments fit in the available height? This must be
        // derived from the real constraint, not a hardcoded number, or the
        // segment column can ask for more height than it's actually given
        // (that's what caused the "overflowed by 2.1 pixels" error).
        final availableHeight =
        constraints.maxHeight.isFinite ? constraints.maxHeight : 96.0;
        final maxSegments =
        (availableHeight / segmentPitch).floor().clamp(4, 30);
        final barMaxHeight = maxSegments * segmentPitch;

        // Resize state arrays if the fitting bar count changed
        // (e.g. on window resize or first layout).
        if (previousHeights.length != barCount) {
          previousHeights = List.filled(barCount, 0);
          peakHeights = List.filled(barCount, 0);
          peakOpacity = List.filled(barCount, 1.0);
          phases = List.generate(
              barCount, (i) => math.Random().nextDouble() * 2 * math.pi);
          barFactors = List.generate(
              barCount, (i) => 0.55 + math.Random().nextDouble() * 0.45);
        }

        return SizedBox(
          width: constraints.maxWidth,
          child: AnimatedBuilder(
            animation: eqController,
            builder: (context, child) {
              final t = eqController.value;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(barCount, (i) {
                  final base = 8.0 + barFactors[i] * 9.0;

                  final bounce =
                      (math.sin(t * 2 * math.pi + phases[i]) + 1) * 22;

                  final targetHeight =
                      base + bounce * (0.65 + barFactors[i] * 0.35);

                  double damping = targetHeight > previousHeights[i]
                      ? 0.35
                      : 0.12 + (previousHeights[i] / 200);

                  final smoothedHeight = previousHeights[i] +
                      (targetHeight - previousHeights[i]) * damping;

                  previousHeights[i] = smoothedHeight;

                  if (smoothedHeight > peakHeights[i]) {
                    peakHeights[i] = smoothedHeight;
                    peakOpacity[i] = 1.0;
                  } else {
                    peakHeights[i] -= 0.6;
                    peakOpacity[i] = (peakOpacity[i] - 0.05).clamp(0.0, 1.0);
                    if (peakHeights[i] < smoothedHeight) {
                      peakHeights[i] = smoothedHeight;
                    }
                  }

                  final displayHeight = playing ? smoothedHeight : base;
                  final activeSegments = (displayHeight / segmentPitch)
                      .clamp(0, maxSegments)
                      .round();
                  final peakSegment = (peakHeights[i] / segmentPitch)
                      .clamp(0, maxSegments)
                      .round();

                  return Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: barHorizontalMargin),
                    width: barWidth,
                    height: barMaxHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: List.generate(maxSegments, (j) {
                        // j counts from the top; convert to "from bottom"
                        // so index 0 is the lowest (blue) segment.
                        final segIndex = maxSegments - 1 - j;
                        final lit = segIndex < activeSegments;
                        final isPeak = segIndex == peakSegment - 1 &&
                            peakOpacity[i] > 0.05;
                        final baseColor =
                        segmentColor(segIndex, maxSegments);
                        final color = isPeak
                            ? Colors.white.withOpacity(peakOpacity[i])
                            : baseColor;

                        return Container(
                          margin: const EdgeInsets.only(bottom: segmentGap),
                          width: barWidth,
                          height: segmentHeight,
                          decoration: BoxDecoration(
                            color: (lit || isPeak)
                                ? color
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(1.5),
                            boxShadow: (lit || isPeak)
                                ? [
                              BoxShadow(
                                color: color.withOpacity(0.7),
                                blurRadius: 4,
                                spreadRadius: 0.5,
                              ),
                            ]
                                : null,
                          ),
                        );
                      }),
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          actions: [
            Builder(
              builder: (buttonContext) => IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                tooltip: "Listener Chat",
                onPressed: () {
                  Navigator.push(
                    buttonContext,
                    MaterialPageRoute(builder: (context) => const ChatScreen()),
                  );
                },
              ),
            ),
          ],
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    "Super Antequera Radio HD",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: isMobile ? 17 : 28,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: livePulse,
                builder: (context, child) {
                  return Opacity(
                    opacity: livePulse.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Text(
                        "LIVE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                "assets/background.png",
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(color: Colors.black.withOpacity(0.0)),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Scale everything down on shorter screens so the whole
                  // layout fits in one viewport instead of needing to scroll.
                  // 830 accounts for the added social banner + its gaps.
                  final scale =
                  (constraints.maxHeight / 830).clamp(0.6, 1.0);

                  final logoSize = (isMobile ? 220.0 : 245.0) * scale;
                  final vinylSize = logoSize;
                  final vinylIconSize = (isMobile ? 90.0 : 70.0) * scale;
                  final titleFontSize = (isMobile ? 19.0 : 24.0) * scale;
                  final artistFontSize = (isMobile ? 15.0 : 18.0) * scale;
                  final gapXl = 24.0 * scale;
                  final gapLg = 10.0 * scale;
                  final gapMd = 12.0 * scale;
                  final gapSm = 6.0 * scale;
                  final panelPadding = 12.0 * scale;
                  final eqHeight = 55.0 * scale;
                  final controlsVPad = 8.0 * scale;

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isMobile ? 340 : 420,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SocialBanner(),
                              SizedBox(height: gapLg),

                              AnimatedBuilder(
                                animation: logoSpinController,
                                builder: (context, child) {
                                  final angle =
                                      logoSpinController.value * 2 * math.pi;
                                  return Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.001)
                                      ..rotateY(angle),
                                    child: child,
                                  );
                                },
                                child: SizedBox(
                                  width: logoSize,
                                  height: logoSize,
                                  child: ShaderMask(
                                    shaderCallback: (bounds) {
                                      return const RadialGradient(
                                        center: Alignment.center,
                                        radius: 0.5,
                                        colors: [
                                          Colors.white,
                                          Colors.white,
                                          Colors.transparent,
                                        ],
                                        stops: [0.0, 0.82, 1.0],
                                      ).createShader(bounds);
                                    },
                                    blendMode: BlendMode.dstIn,
                                    child: Image.asset(
                                      "assets/radio_logo.png",
                                      width: logoSize,
                                      height: logoSize,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 0),

                              RotationTransition(
                                turns: vinylController,
                                child: Container(
                                  width: vinylSize,
                                  height: vinylSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withOpacity(0.2),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: artworkUrl != null
                                        ? Container(
                                      color: Colors.black,
                                      child: Center(
                                        child: FractionallySizedBox(
                                          widthFactor: 0.98,
                                          heightFactor: 0.98,
                                          child: ShaderMask(
                                            shaderCallback: (bounds) {
                                              return const RadialGradient(
                                                center: Alignment.center,
                                                radius: 0.5,
                                                colors: [
                                                  Colors.white,
                                                  Colors.white,
                                                  Colors.transparent,
                                                ],
                                                stops: [0.0, 0.9, 1.0],
                                              ).createShader(bounds);
                                            },
                                            blendMode: BlendMode.dstIn,
                                            child: Image.network(
                                              artworkUrl!,
                                              fit: BoxFit.cover,
                                              alignment:
                                              const Alignment(0, -0.5),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                        : Icon(
                                      Icons.album,
                                      color: Colors.white54,
                                      size: vinylIconSize,
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: gapXl),

                              Text(
                                title ?? "Loading…",
                                style: GoogleFonts.montserrat(
                                  color: Colors.white,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              SizedBox(height: gapSm),

                              Text(
                                artist ?? "",
                                style: GoogleFonts.montserrat(
                                  color: Colors.white70,
                                  fontSize: artistFontSize,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              SizedBox(height: gapXl),

                              frostedPanel(
                                padding: panelPadding,
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: eqHeight,
                                      width: double.infinity,
                                      child: buildAudioEqualizer(),
                                    ),

                                    SizedBox(height: gapLg),

                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        vertical: controlsVPad,
                                        horizontal: 24 * scale,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius:
                                        BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                        children: [
                                          Icon(
                                            Icons.skip_previous,
                                            color: Colors.white,
                                            size: 28 * scale,
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              playing
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white,
                                              size: 36 * scale,
                                            ),
                                            onPressed: () => playing
                                                ? audioHandler.pause()
                                                : audioHandler.play(),
                                          ),
                                          Icon(
                                            Icons.skip_next,
                                            color: Colors.white,
                                            size: 28 * scale,
                                          ),
                                        ],
                                      ),
                                    ),

                                    SizedBox(height: gapLg),

                                    Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.volume_mute,
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: volume,
                                            min: 0,
                                            max: 100,
                                            activeColor: Colors.white,
                                            inactiveColor: Colors.white24,
                                            onChanged: (v) {
                                              setState(() => volume = v);
                                              player.setVolume(v);
                                            },
                                          ),
                                        ),
                                        Icon(
                                          Icons.volume_up,
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: gapSm),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}