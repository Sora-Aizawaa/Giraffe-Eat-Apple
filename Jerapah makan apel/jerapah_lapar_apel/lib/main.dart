// =====================================================================
// JERAPAH LAPAR APEL
// -----------------------------------------------------------------
// Game sederhana: pohon terus berbuah apel (ada yang segar/merah,
// ada yang busuk). Jerapah menjulurkan lidah untuk memakan apel yang
// disentuh pemain. Apel segar menambah skor & sedikit nyawa, apel
// busuk mengurangi nyawa. Jerapah makin "gendut" seiring skor naik.
// Game selesai (MENANG) saat seluruh apel di "kolam suplai" habis
// dimakan. Game KALAH kalau nyawa jerapah habis (0).
//
// Semua grafis (jerapah, apel, pohon, langit) digambar langsung
// dengan CustomPainter (vector) -> tidak perlu file aset gambar
// eksternal sama sekali, jadi tidak ada masalah "aset hilang".
// =====================================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const JerapahApp());
}

class JerapahApp extends StatelessWidget {
  const JerapahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jerapah Lapar Apel',
      theme: ThemeData(useMaterial3: true),
      home: const GamePage(),
    );
  }
}

// ---------------------------------------------------------------------
// MODEL DATA
// ---------------------------------------------------------------------

enum AppleKind { segar, busuk }

enum GameStatus { playing, won, lost }

class AppleData {
  final AppleKind kind;
  bool targeted = false; // sedang dituju lidah jerapah (mencegah tap dobel)
  bool consumed = false; // sudah "digigit" -> animasi mengecil/hilang
  AppleData(this.kind);
}

// teks feedback melayang ("Yummy!", "Yuck!", dst) saat apel dimakan
class _FloatText {
  final int id;
  final String text;
  final Offset pos;
  final bool good;
  _FloatText(
      {required this.id,
      required this.text,
      required this.pos,
      required this.good});
}

const List<String> kGoodWords = [
  'Yummy!',
  'Delicious!',
  'Nom nom!',
  'Tasty!',
  'Yum!',
  'So good!',
  'Crunchy!',
  'Munch munch!',
  'Sweet!',
  'More please!',
];
const List<String> kBadWords = [
  'Yuck!',
  'Eww!',
  'Bleh!',
  'Rotten!',
  'Ugh!',
  'Gross!',
  'Not again!',
  'Blegh!',
];

// --- cerita reward: muncul saat skor mencapai ambang tertentu ---
class StoryMilestone {
  final int score;
  final String title;
  final String text;
  const StoryMilestone(
      {required this.score, required this.title, required this.text});
}

const List<StoryMilestone> kStoryMilestones = [
  StoryMilestone(
    score: 30,
    title: 'A New Friend',
    text:
        'Meet Georgie! Once the skinniest giraffe in the valley, she wandered into an old '
        "orchard looking for a bite to eat. Little did she know, this apple tree would "
        'change everything.',
  ),
  StoryMilestone(
    score: 70,
    title: 'Getting Comfy',
    text:
        "Georgie's neck aches from all that stretching, but her tummy finally feels warm "
        "and full. The village kids have started calling her the Apple Whisperer.",
  ),
  StoryMilestone(
    score: 120,
    title: 'Growing Strong',
    text:
        "With every apple, Georgie's coat grows shinier and her steps a little bouncier. "
        "Even grumpy old Farmer Tom swears she's smiling more these days.",
  ),
  StoryMilestone(
    score: 170,
    title: 'Local Legend',
    text:
        'Word has spread across the valley about a giraffe who can clear an entire orchard '
        'in one afternoon. Georgie is quickly becoming a local legend.',
  ),
  StoryMilestone(
    score: 220,
    title: "Season's Reward",
    text:
        'The orchard is nearly bare, and Georgie stands tall, round, and happier than ever. '
        "She promises to visit again next season -- after all, apples never stay ripe for "
        'long!',
  ),
];

// ---------------------------------------------------------------------
// KONFIGURASI GAME
// ---------------------------------------------------------------------

const double kRottenChance = 0.28; // peluang sebuah apel baru busuk
const Duration kSpawnInterval =
    Duration(milliseconds: 750); // pohon "cepat berbuah"

// posisi slot apel di kanopi pohon (fraksi 0..1 dari ukuran layar)
const List<Offset> kSlotFractions = [
  Offset(0.12, 0.24),
  Offset(0.28, 0.15),
  Offset(0.40, 0.26),
  Offset(0.16, 0.38),
  Offset(0.34, 0.40),
  Offset(0.06, 0.33),
];

const Offset kMouthFraction =
    Offset(0.40, 0.24); // titik mulut jerapah (dekat kanopi)

// ---------------------------------------------------------------------
// HALAMAN GAME
// ---------------------------------------------------------------------

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  // --- animation controllers ---
  late final AnimationController _tongueCtrl; // lidah menjulur (0 -> 1)
  late final AnimationController
      _swallowCtrl; // gumpalan tertelan menyusuri leher
  late final AnimationController _fatnessCtrl; // 0 (kurus) -> 1 (gendut)
  late final AnimationController _idleCtrl; // nafas halus / idle
  late final AnimationController _swayCtrl; // goyangan apel di pohon

  // --- state game ---
  late List<AppleData?> slots;
  int currentLevel = 1;
  bool isBathing = false;
  int score = 0;
  double health = 100;
  int goodEaten = 0;
  late final int totalGoodTarget;
  GameStatus status = GameStatus.playing;
  bool giraffeBusy = false;
  int? activeSlotIndex;

  Timer? _spawnTimer;
  final Random _rnd = Random();

  // teks feedback melayang ("Yummy!" dsb)
  final List<_FloatText> floatingTexts = [];
  int _floatIdCounter = 0;

  // musik latar
  final AudioPlayer _bgPlayer = AudioPlayer();
  bool _musicStarted = false;
  bool _musicMuted = false;

  // cerita reward
  final Set<int> _shownMilestones = {};
  StoryMilestone? activeStory;

  // --- kepala jerapah mengikuti drag (mouse / mousepad) ---
  Offset _headDragTarget =
      Offset.zero; // pergeseran (delta px) yang ingin dicapai, dari drag
  Offset _headDragCurrent =
      Offset.zero; // pergeseran yang benar-benar digambar (mengejar dgn halus)
  late final Ticker _followTicker;
  Duration _lastTickElapsed = Duration.zero;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    totalGoodTarget = 50; // total 50 apples for level 5 (500 score)

    _followTicker = createTicker(_onFollowTick)..start();

    _tongueCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _swallowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fatnessCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _idleCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _swayCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();

    slots = List<AppleData?>.filled(kSlotFractions.length, null);
    _startSpawning();
  }

  // Dipanggil tiap frame oleh _followTicker. Kepala jerapah "mengejar"
  // posisi target drag secara halus (bukan langsung loncat ke posisi
  // mouse), pakai interpolasi berbasis waktu supaya konsisten di HP/PC
  // dengan refresh rate berbeda-beda.
  void _onFollowTick(Duration elapsed) {
    final dt = (elapsed - _lastTickElapsed).inMicroseconds / 1e6;
    _lastTickElapsed = elapsed;
    if (dt <= 0 || dt > 0.25)
      return; // lewati lonjakan aneh (mis. app baru resume)

    final catchUp = (dt * 18).clamp(0.0, 1.0);
    final next = Offset.lerp(_headDragCurrent, _headDragTarget, catchUp)!;
    if ((next - _headDragCurrent).distance > 0.05) {
      setState(() => _headDragCurrent = next);
    }

    _checkHeadAppleCollision();
  }

  // Kalau posisi kepala jerapah saat ini (dasar + geseran drag) cukup
  // dekat dengan salah satu apel di pohon, langsung makan otomatis
  // tanpa perlu tap.
  void _checkHeadAppleCollision() {
    if (status != GameStatus.playing) return;
    if (giraffeBusy) return;
    if (_canvasSize == Size.zero) return;

    final mouth = Offset(
          kMouthFraction.dx * _canvasSize.width,
          kMouthFraction.dy * _canvasSize.height,
        ) +
        _headDragCurrent;

    const collisionRadius = 30.0;
    for (int i = 0; i < slots.length; i++) {
      final apple = slots[i];
      if (apple == null || apple.targeted) continue;
      final f = kSlotFractions[i];
      final applePos =
          Offset(f.dx * _canvasSize.width, f.dy * _canvasSize.height);
      if ((mouth - applePos).distance <= collisionRadius) {
        _eatApple(i);
        break; // satu per satu tiap frame supaya animasi makan rapi
      }
    }
  }

  void _onHeadPanUpdate(DragUpdateDetails details) {
    if (status != GameStatus.playing) return;
    // Radius jangkauan diperbesar (dulu 0.16 -> kepala kerasa "tertahan").
    // Delta juga dikali sensitivitas supaya gerakan mouse/jari kecil
    // tetap terasa responsif menggerakkan kepala jerapah.
    final maxRadius =
        _canvasSize.shortestSide == 0 ? 160.0 : _canvasSize.shortestSide * 0.42;
    const dragSensitivity = 1.6;
    var next = _headDragTarget + details.delta * dragSensitivity;
    if (next.distance > maxRadius) {
      next = next / next.distance * maxRadius;
    }
    setState(() => _headDragTarget = next);
  }

  void _onHeadPanEnd(DragEndDetails details) {
    // lepas drag -> muka jerapah "pegas" balik ke posisi semula
    setState(() => _headDragTarget = Offset.zero);
  }

  // Musik baru mulai diputar setelah gestur pertama dari pemain (bukan
  // langsung di initState) -- ini menghindari kebijakan autoplay
  // browser (Chrome/Edge) yang memblokir audio sebelum ada interaksi.
  Future<void> _ensureMusicStarted() async {
    if (_musicStarted) return;
    _musicStarted = true;
    try {
      await _bgPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgPlayer.setVolume(_musicMuted ? 0 : 0.55);
      await _bgPlayer.play(AssetSource('audio/rain.wav'));
    } catch (_) {
      // kalau gagal (mis. aset belum ke-load / device tanpa audio),
      // game tetap harus bisa dimainkan normal tanpa musik.
    }
  }

  void _toggleMute() {
    setState(() => _musicMuted = !_musicMuted);
    _bgPlayer.setVolume(_musicMuted ? 0 : 0.55);
  }

  // Cek apakah skor sudah melewati salah satu ambang cerita reward.
  // Ditampilkan satu per satu (bukan numpuk) & permainan dijeda
  // sebentar (spawn apel berhenti) selama cerita dibaca.
  void _checkStoryMilestones() {
    for (final m in kStoryMilestones) {
      if (score >= m.score && !_shownMilestones.contains(m.score)) {
        _shownMilestones.add(m.score);
        _spawnTimer?.cancel();
        setState(() => activeStory = m);
        break;
      }
    }
  }

  void _dismissStory() {
    setState(() => activeStory = null);
    if (status == GameStatus.playing) _startSpawning();
  }

  void _startSpawning() {
    _spawnTimer?.cancel();
    _spawnTimer = Timer.periodic(kSpawnInterval, (_) {
      if (status != GameStatus.playing) return;

      final emptyIdx = <int>[];
      for (int i = 0; i < slots.length; i++) {
        if (slots[i] == null) emptyIdx.add(i);
      }
      if (emptyIdx.isEmpty) return;

      final idx = emptyIdx[_rnd.nextInt(emptyIdx.length)];
      final kind =
          _rnd.nextDouble() < kRottenChance ? AppleKind.busuk : AppleKind.segar;

      setState(() {
        slots[idx] = AppleData(kind);
      });
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _followTicker.dispose();
    _bgPlayer.dispose();
    _tongueCtrl.dispose();
    _swallowCtrl.dispose();
    _fatnessCtrl.dispose();
    _idleCtrl.dispose();
    _swayCtrl.dispose();
    super.dispose();
  }

  Future<void> _eatApple(int index) async {
    if (status != GameStatus.playing) return;
    if (giraffeBusy) return;
    final apple = slots[index];
    if (apple == null || apple.targeted) return;

    setState(() {
      giraffeBusy = true;
      activeSlotIndex = index;
      apple.targeted = true;
    });

    // 1) lidah menjulur menuju apel
    await _tongueCtrl.forward(from: 0);
    if (!mounted) return;

    // 2) apel "digigit" -> mulai mengecil/hilang & efek ke nyawa/skor
    setState(() {
      apple.consumed = true;
      if (apple.kind == AppleKind.segar) {
        score += 10;
        goodEaten++;
        health = min(100, health + 2);
      } else {
        health = max(0, health - 20);
      }
    });

    if (_canvasSize != Size.zero) {
      final f = kSlotFractions[index];
      final applePos =
          Offset(f.dx * _canvasSize.width, f.dy * _canvasSize.height);
      final good = apple.kind == AppleKind.segar;
      final word = good
          ? kGoodWords[_rnd.nextInt(kGoodWords.length)]
          : kBadWords[_rnd.nextInt(kBadWords.length)];
      _addFloatText(word, applePos, good);
    }

    _fatnessCtrl.animateTo(
      min(1, goodEaten / totalGoodTarget),
      curve: Curves.easeOutBack,
    );

    // 3) gumpalan tertelan menyusuri leher, bersamaan lidah ditarik kembali
    unawaited(_swallowCtrl.forward(from: 0));
    await Future.wait([
      _tongueCtrl.reverse(),
      Future.delayed(const Duration(milliseconds: 320)), // waktu apel mengecil
    ]);
    if (!mounted) return;

    setState(() {
      slots[index] = null;
      giraffeBusy = false;
      activeSlotIndex = null;
    });

    _checkGameEnd();
  }

  void _addFloatText(String text, Offset pos, bool good) {
    final id = _floatIdCounter++;
    setState(() {
      floatingTexts.add(_FloatText(id: id, text: text, pos: pos, good: good));
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => floatingTexts.removeWhere((t) => t.id == id));
    });
  }

  void _checkGameEnd() {
    if (health <= 0) {
      _spawnTimer?.cancel();
      setState(() => status = GameStatus.lost);
      return;
    }
    
    if (score >= currentLevel * 100) {
      if (currentLevel < 5) {
        // Level up
        setState(() {
          currentLevel++;
          slots = List<AppleData?>.filled(kSlotFractions.length, null);
        });
      } else if (currentLevel == 5 && score >= 500) {
        _spawnTimer?.cancel();
        setState(() {
          status = GameStatus.won;
          isBathing = true;
        });
      }
    }
  }

  void _restart() {
    _spawnTimer?.cancel();
    setState(() {
      slots = List<AppleData?>.filled(kSlotFractions.length, null);
      currentLevel = 1;
      isBathing = false;
      score = 0;
      health = 100;
      goodEaten = 0;
      status = GameStatus.playing;
      giraffeBusy = false;
      activeSlotIndex = null;
      _headDragTarget = Offset.zero;
      _headDragCurrent = Offset.zero;
      floatingTexts.clear();
      _shownMilestones.clear();
      activeStory = null;
    });
    _fatnessCtrl.value = 0;
    _startSpawning();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8ED1FC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          _canvasSize = size; // dipakai buat batas jarak drag kepala

          return GestureDetector(
            // area drag mencakup seluruh layar -> pemain bisa tarik di
            // mana saja (mouse di desktop/web, jari di mousepad/HP) dan
            // kepala jerapah akan mengikuti dengan gerakan halus.
            behavior: HitTestBehavior.translucent,
            onPanDown: (_) => _ensureMusicStarted(),
            onPanUpdate: _onHeadPanUpdate,
            onPanEnd: _onHeadPanEnd,
            child: Stack(
              children: [
                // latar: langit, tanah, batang & kanopi pohon
                const Positioned.fill(
                    child: CustomPaint(painter: _ScenePainter())),

                // apel-apel di pohon (widget terpisah supaya bisa di-tap & animasi mudah)
                ..._buildApples(size),

                // jerapah (badan, leher, kepala, lidah, animasi tertelan)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                      [_tongueCtrl, _swallowCtrl, _fatnessCtrl, _idleCtrl],
                    ),
                    builder: (context, _) {
                      Offset? target;
                      if (activeSlotIndex != null) {
                        final f = kSlotFractions[activeSlotIndex!];
                        target = Offset(f.dx * size.width, f.dy * size.height);
                      }
                      return CustomPaint(
                        painter: _GiraffePainter(
                          tongueT: _tongueCtrl.value,
                          swallowT: _swallowCtrl.value,
                          fatness: _fatnessCtrl.value,
                          idleT: _idleCtrl.value,
                          target: target,
                          headOffset: _headDragCurrent,
                          isBathing: isBathing,
                        ),
                      );
                    },
                  ),
                ),

                _buildHud(),
                ..._buildFloatingTexts(),
                if (status != GameStatus.playing) _buildOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildFloatingTexts() {
    return floatingTexts.map((t) {
      return TweenAnimationBuilder<double>(
        key: ValueKey(t.id),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        builder: (context, v, child) {
          return Positioned(
            left: t.pos.dx - 50,
            top: t.pos.dy - 20 - (v * 40), // melayang naik
            width: 100,
            child: Opacity(
              opacity: 1 - v,
              child: Text(
                t.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: t.good
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF6D4C1B),
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black45),
                    Shadow(blurRadius: 1, color: Colors.white70),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  List<Widget> _buildApples(Size size) {
    final widgets = <Widget>[];
    for (int i = 0; i < slots.length; i++) {
      final apple = slots[i];
      if (apple == null) continue;
      final f = kSlotFractions[i];
      final pos = Offset(f.dx * size.width, f.dy * size.height);

      widgets.add(
        AnimatedBuilder(
          animation: _swayCtrl,
          builder: (context, _) {
            final phase = i * 0.8;
            final angle = sin((_swayCtrl.value * 2 * pi) + phase) * 0.12;
            return Positioned(
              left: pos.dx - 16,
              top: pos.dy - 16,
              width: 32,
              height: 32,
              child: Transform.rotate(
                angle: angle,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _eatApple(i),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: apple.consumed ? 0.0 : 1.0),
                    duration: const Duration(milliseconds: 320),
                    curve: apple.consumed ? Curves.easeIn : Curves.elasticOut,
                    builder: (context, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: CustomPaint(
                      size: const Size(32, 32),
                      painter: _ApplePainter(kind: apple.kind),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return widgets;
  }

  Widget _buildHud() {
    return Positioned(
      top: 40,
      left: 16,
      right: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Score: $score',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                  ),
                ),
                const SizedBox(height: 6),
                // Lebar health bar dibatasi maksimal 160px, tapi kalau
                // ruang yang tersedia lebih sempit (layar/window kecil)
                // ia otomatis menyusut mengikuti `constraints.maxWidth`
                // dari LayoutBuilder -> tidak overflow lagi.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final barWidth = constraints.maxWidth.isFinite
                        ? min(160.0, constraints.maxWidth)
                        : 160.0;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: barWidth,
                        height: 14,
                        child: Stack(
                          children: [
                            Container(color: Colors.black26),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: barWidth * (health / 100),
                              color: health > 50
                                  ? Colors.green
                                  : (health > 20 ? Colors.orange : Colors.red),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  'Health: ${health.toInt()}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Level: $currentLevel',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                  ),
                ),
                Text(
                  'In Tree: ${slots.where((s) => s != null).length}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleMute,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _musicMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryOverlay(StoryMilestone story) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E0),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE0A93F), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🦒', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(
                  'Score ${story.score} Reward!',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB5772A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  story.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B3410),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  story.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF4A3320),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _dismissStory,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE0A93F)),
                  child: const Text('Continue',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final won = status == GameStatus.won;
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  won ? 'All Apples Eaten! You Win!' : 'Giraffe Starved...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: won ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Final Score: $score',
                    style: const TextStyle(fontSize: 18)),
                Text(
                  'Fresh apples eaten: $goodEaten',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _restart,
                  child: const Text('Play Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// PAINTER: LATAR (langit, tanah, pohon)
// ---------------------------------------------------------------------

const List<Offset> kFoliageCenters = [
  Offset(0.22, 0.26),
  Offset(0.10, 0.32),
  Offset(0.34, 0.30),
  Offset(0.18, 0.16),
  Offset(0.30, 0.18),
  Offset(0.08, 0.20),
];

class _ScenePainter extends CustomPainter {
  const _ScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final skyRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF8ED1FC), Color(0xFFE3F6FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(skyRect),
    );

    // matahari
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.12),
      size.width * 0.07,
      Paint()..color = const Color(0xFFFFE08A),
    );

    // awan
    _cloud(canvas, Offset(size.width * 0.75, size.height * 0.20),
        size.width * 0.09);
    _cloud(canvas, Offset(size.width * 0.60, size.height * 0.09),
        size.width * 0.06);

    // tanah
    final groundRect =
        Rect.fromLTWH(0, size.height * 0.82, size.width, size.height * 0.18);
    canvas.drawRect(groundRect, Paint()..color = const Color(0xFF8FCB63));
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.82, size.width, 6),
      Paint()..color = const Color(0xFF6FAE49),
    );

    // batang pohon
    final trunkRect = Rect.fromLTWH(
      size.width * 0.185,
      size.height * 0.32,
      size.width * 0.06,
      size.height * 0.52,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trunkRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF7A4A25),
    );

    // kanopi daun (gerombolan lingkaran hijau)
    final leafPaint = Paint()..color = const Color(0xFF4C9A4C);
    final leafOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF3A7A3A).withValues(alpha: 0.4);

    for (final c in kFoliageCenters) {
      final center = Offset(c.dx * size.width, c.dy * size.height);
      canvas.drawCircle(center, size.width * 0.11, leafPaint);
    }
    for (final c in kFoliageCenters) {
      final center = Offset(c.dx * size.width, c.dy * size.height);
      canvas.drawCircle(center, size.width * 0.11, leafOutline);
    }
  }

  void _cloud(Canvas canvas, Offset center, double r) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(center, r, p);
    canvas.drawCircle(center + Offset(r * 0.8, 0), r * 0.7, p);
    canvas.drawCircle(center + Offset(-r * 0.8, 0), r * 0.7, p);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------
// PAINTER: APEL
// ---------------------------------------------------------------------

class _ApplePainter extends CustomPainter {
  final AppleKind kind;
  const _ApplePainter({required this.kind});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 2);
    final radius = size.width / 2 - 2;
    final color = kind == AppleKind.segar
        ? const Color(0xFFE23B3B)
        : const Color(0xFF7A5C3E);

    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.25),
    );

    // kilau
    canvas.drawCircle(
      center + Offset(-radius * 0.35, -radius * 0.35),
      radius * 0.22,
      Paint()
        ..color = Colors.white
            .withValues(alpha: kind == AppleKind.segar ? 0.55 : 0.25),
    );

    // tangkai
    canvas.drawLine(
      center + Offset(0, -radius),
      center + Offset(0, -radius - 6),
      Paint()
        ..color = const Color(0xFF5B3A1E)
        ..strokeWidth = 3,
    );

    // daun kecil
    canvas.drawOval(
      Rect.fromCenter(
          center: center + Offset(6, -radius - 2), width: 10, height: 6),
      Paint()..color = const Color(0xFF4C8C3B),
    );

    if (kind == AppleKind.busuk) {
      final spotPaint = Paint()..color = const Color(0xFF3E2A18);
      final rnd = Random(size.width.toInt() + size.height.toInt() + 7);
      for (int i = 0; i < 5; i++) {
        canvas.drawCircle(
          center +
              Offset((rnd.nextDouble() - 0.5) * radius,
                  (rnd.nextDouble() - 0.5) * radius),
          2 + rnd.nextDouble() * 2,
          spotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ApplePainter oldDelegate) =>
      oldDelegate.kind != kind;
}

// ---------------------------------------------------------------------
// PAINTER: JERAPAH
// ---------------------------------------------------------------------

class _GiraffePainter extends CustomPainter {
  final double tongueT; // 0..1 lidah menjulur
  final double swallowT; // 0..1 gumpalan tertelan
  final double fatness; // 0..1 kurus -> gendut
  final double idleT; // 0..1 animasi nafas
  final Offset? target; // posisi apel yang sedang dituju (absolut px)
  final Offset headOffset; // pergeseran mulut/kepala akibat drag mouse/mousepad
  final bool isBathing; // true jika animasi mandi (level 5 menang)

  const _GiraffePainter({
    required this.tongueT,
    required this.swallowT,
    required this.fatness,
    required this.idleT,
    required this.target,
    this.headOffset = Offset.zero,
    this.isBathing = false,
  });

  static const Offset bodyFrac = Offset(0.64, 0.74);

  @override
  void paint(Canvas canvas, Size size) {
    final bodyCenter =
        Offset(bodyFrac.dx * size.width, bodyFrac.dy * size.height);
    final mouth = Offset(
            kMouthFraction.dx * size.width, kMouthFraction.dy * size.height) +
        headOffset;
    final breathe = 1 + 0.02 * sin(idleT * 2 * pi);

    final furColor = const Color(0xFFF4C15C);
    final furPaint = Paint()..color = furColor;
    final spotPaint = Paint()..color = const Color(0xFF8B4A1F);
    final darkOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF6B3410);

    final bodyWidth = size.width * (0.20 + 0.10 * fatness) * breathe;
    final bodyHeight = size.height * (0.16 + 0.04 * fatness) * breathe;
    final bodyRect = Rect.fromCenter(
        center: bodyCenter, width: bodyWidth, height: bodyHeight);

    // titik pangkal leher dihitung DARI badan (bukan fraksi layar
    // terpisah) supaya leher selalu menempel rapat ke badan, berapa
    // pun ukuran/gendutnya badan saat itu -> tidak ada celah "bolong"
    // di antara leher dan badan.
    final neckBase = Offset(
      bodyCenter.dx - bodyWidth * 0.10,
      bodyCenter.dy - bodyHeight * 0.30,
    );

    // --- kaki ---
    final legPaint = Paint()..color = furColor;
    for (final dx in [-0.32, -0.10, 0.10, 0.32]) {
      final legTop = Offset(
          bodyCenter.dx + dx * bodyWidth, bodyCenter.dy + bodyHeight * 0.35);
      final legRect =
          Rect.fromLTWH(legTop.dx - 6, legTop.dy, 12, size.height * 0.16);
      final rrect = RRect.fromRectAndRadius(legRect, const Radius.circular(6));
      canvas.drawRRect(rrect, legPaint);
      canvas.drawRRect(rrect, darkOutline);
    }

    // --- ekor ---
    final tailBase = Offset(bodyCenter.dx - bodyWidth * 0.48, bodyCenter.dy);
    canvas.drawLine(
      tailBase,
      tailBase + const Offset(-14, 20),
      Paint()
        ..color = furColor
        ..strokeWidth = 4,
    );

    // --- leher ---
    final neckWidth = 26 + 10 * fatness;
    final control =
        Offset((neckBase.dx + mouth.dx) / 2 - 20, (neckBase.dy + mouth.dy) / 2);
    final neckPath = Path()
      ..moveTo(neckBase.dx - neckWidth / 2, neckBase.dy)
      ..quadraticBezierTo(control.dx - neckWidth / 2, control.dy,
          mouth.dx - neckWidth / 3, mouth.dy)
      ..lineTo(mouth.dx + neckWidth / 3, mouth.dy)
      ..quadraticBezierTo(control.dx + neckWidth / 2, control.dy,
          neckBase.dx + neckWidth / 2, neckBase.dy)
      ..close();
    canvas.drawPath(neckPath, furPaint);
    canvas.drawPath(neckPath, darkOutline);

    // bintik di leher
    final rndNeckSpots = Random(7);
    for (int i = 0; i < 9; i++) {
      final t = (i / 9).clamp(0.08, 0.9);
      final p = _quadPoint(neckBase, control, mouth, t);
      canvas.drawCircle(
          p + Offset((rndNeckSpots.nextDouble() - 0.5) * 10, 0), 5, spotPaint);
    }

    // --- badan ---
    canvas.drawOval(bodyRect, furPaint);
    canvas.drawOval(bodyRect, darkOutline);

    // bintik-bintik badan
    final rndSpots = Random(42);
    final spotCount = 8 + (fatness * 6).round();
    for (int i = 0; i < spotCount; i++) {
      final ox =
          bodyCenter.dx + (rndSpots.nextDouble() - 0.5) * bodyWidth * 0.8;
      final oy =
          bodyCenter.dy + (rndSpots.nextDouble() - 0.5) * bodyHeight * 0.7;
      canvas.drawCircle(
          Offset(ox, oy), 6 + rndSpots.nextDouble() * 4, spotPaint);
    }

    // --- kepala ---
    final headCenter = mouth + const Offset(0, -14);
    final headRect = Rect.fromCenter(center: headCenter, width: 34, height: 26);
    canvas.drawOval(headRect, furPaint);
    canvas.drawOval(headRect, darkOutline);

    // ossicone (tanduk kecil khas jerapah)
    canvas.drawCircle(headCenter + const Offset(-8, -16), 4, spotPaint);
    canvas.drawCircle(headCenter + const Offset(8, -16), 4, spotPaint);

    // mata
    canvas.drawCircle(
        headCenter + const Offset(-8, -2), 3, Paint()..color = Colors.black);
    canvas.drawCircle(
        headCenter + const Offset(8, -2), 3, Paint()..color = Colors.black);

    // --- lidah menjulur ---
    if (target != null && tongueT > 0.01) {
      final tip = Offset.lerp(mouth, target!, tongueT)!;
      final tonguePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE0526B);
      canvas.drawLine(mouth, tip, tonguePaint);
      canvas.drawCircle(tip, 6, Paint()..color = const Color(0xFFE0526B));
    }

    // --- gumpalan tertelan menyusuri leher (mouth -> body) ---
    if (swallowT > 0.0 && swallowT < 1.0) {
      final p = _quadPoint(neckBase, control, mouth, 1 - swallowT);
      canvas.drawCircle(
        p,
        10 + 4 * sin(swallowT * pi),
        Paint()..color = const Color(0xFFCF7A2E),
      );
    }

    // --- animasi mandi (bathtub) ---
    if (isBathing) {
      // draw bathtub covering lower body
      final tubRect = Rect.fromLTWH(
        bodyCenter.dx - bodyWidth * 0.8,
        bodyCenter.dy + bodyHeight * 0.1,
        bodyWidth * 1.6,
        bodyHeight * 0.8,
      );
      final tubPath = Path()
        ..moveTo(tubRect.left, tubRect.top)
        ..lineTo(tubRect.right, tubRect.top)
        ..quadraticBezierTo(
            tubRect.right, tubRect.bottom, tubRect.right - 20, tubRect.bottom)
        ..lineTo(tubRect.left + 20, tubRect.bottom)
        ..quadraticBezierTo(
            tubRect.left, tubRect.bottom, tubRect.left, tubRect.top)
        ..close();
      canvas.drawPath(tubPath, Paint()..color = Colors.white);
      canvas.drawPath(
          tubPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.grey[400]!);

      // water and bubbles
      final waterPaint = Paint()..color = const Color(0xAA42A5F5);
      canvas.drawRect(
        Rect.fromLTWH(tubRect.left + 5, tubRect.top + 5, tubRect.width - 10,
            tubRect.height * 0.4),
        waterPaint,
      );

      final rnd = Random(123);
      for (int i = 0; i < 15; i++) {
        final bx = tubRect.left + 20 + rnd.nextDouble() * (tubRect.width - 40);
        final by = tubRect.top - 10 + rnd.nextDouble() * 30 + sin(idleT * 2 * pi + i) * 5;
        final br = 3 + rnd.nextDouble() * 8;
        canvas.drawCircle(Offset(bx, by), br, Paint()..color = Colors.white.withValues(alpha: 0.6));
      }
    }
  }

  Offset _quadPoint(Offset p0, Offset p1, Offset p2, double t) {
    final x =
        (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
    final y =
        (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _GiraffePainter oldDelegate) =>
      oldDelegate.tongueT != tongueT ||
      oldDelegate.swallowT != swallowT ||
      oldDelegate.fatness != fatness ||
      oldDelegate.idleT != idleT ||
      oldDelegate.target != target ||
      oldDelegate.headOffset != headOffset ||
      oldDelegate.isBathing != isBathing;
}
