import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MimoNdiApp());
}

class MimoNdiApp extends StatelessWidget {
  const MimoNdiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIMO_NDI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6200EE),
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// NAVIGATION PRINCIPALE
// ─────────────────────────────────────────────
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<String> _titles = ["Réception Flux", "Transmettre Caméra", "Multiview 4"];

  List<Widget> get _pages => [
        const NdiReceiveScreen(),
        const NdiSendScreen(),
        const MultiviewScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('IMG_0730.JPG'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.3),
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          title: Text(_titles[_selectedIndex],
              style: const TextStyle(
                  fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          centerTitle: true,
        ),
        drawer: _buildDrawer(),
        body: _pages[_selectedIndex],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.black.withOpacity(0.8),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('IMG_0730.JPG'),
                fit: BoxFit.cover,
                colorFilter:
                    ColorFilter.mode(Colors.black38, BlendMode.darken),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                CircleAvatar(
                    radius: 30,
                    backgroundImage: AssetImage('IMG_0730.JPG')),
                SizedBox(height: 10),
                Text('MIMO_NDI',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                Text('Professional Broadcast',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          _drawerItem(0, Icons.download, 'Recevoir Flux'),
          _drawerItem(1, Icons.videocam, 'Transmettre Caméra'),
          _drawerItem(2, Icons.grid_view, 'Multiview 4'),
          const Divider(color: Colors.white24),
          ListTile(
            leading:
                const Icon(Icons.info_outline, color: Colors.white70),
            title: const Text('À propos'),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(int index, IconData icon, String title) {
    bool isSelected = _selectedIndex == index;
    return ListTile(
      selected: isSelected,
      selectedTileColor: Colors.white10,
      leading: Icon(icon,
          color: isSelected ? Colors.greenAccent : Colors.white70),
      title: Text(title,
          style: TextStyle(
              color: isSelected ? Colors.greenAccent : Colors.white)),
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }
}

// ─────────────────────────────────────────────
// ÉCRAN RÉCEPTION - LISTE DES SOURCES
// ─────────────────────────────────────────────
class NdiReceiveScreen extends StatefulWidget {
  const NdiReceiveScreen({super.key});

  @override
  State<NdiReceiveScreen> createState() => _NdiReceiveScreenState();
}

class _NdiReceiveScreenState extends State<NdiReceiveScreen> {
  static const _channel = MethodChannel('com.antigravity/ndi');
  List<String> _sources = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      final List<dynamic>? result =
          await _channel.invokeMethod('getSources');
      if (mounted) {
        setState(() {
          _sources = result?.cast<String>() ?? [];
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _openPlayer(String source) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NdiPlayerScreen(sourceName: source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header sources
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SOURCES DISPONIBLES',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white54)),
              _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      onPressed: _startScan,
                      icon: const Icon(Icons.refresh, size: 20)),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        Expanded(
          child: _sources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 48, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                          _isScanning
                              ? 'Recherche de sources NDI...'
                              : 'Aucune source trouvée',
                          style: const TextStyle(color: Colors.white38)),
                      if (!_isScanning) ...[
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Rechercher'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              foregroundColor: Colors.black),
                        )
                      ]
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  itemCount: _sources.length,
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.12)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.greenAccent.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.sensors,
                                    color: Colors.greenAccent),
                              ),
                              title: Text(source,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              subtitle: const Text('NDI® Source',
                                  style: TextStyle(color: Colors.white38)),
                              trailing: const Icon(Icons.play_circle_fill,
                                  color: Colors.greenAccent, size: 34),
                              // ✅ UN SEUL CLIC → PLEIN ÉCRAN IMMÉDIATEMENT
                              onTap: () => _openPlayer(source),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ÉCRAN LECTEUR PLEIN ÉCRAN NDI
// ─────────────────────────────────────────────
class NdiPlayerScreen extends StatefulWidget {
  final String sourceName;
  const NdiPlayerScreen({super.key, required this.sourceName});

  @override
  State<NdiPlayerScreen> createState() => _NdiPlayerScreenState();
}

class _NdiPlayerScreenState extends State<NdiPlayerScreen> {
  static const _channel = MethodChannel('com.antigravity/ndi');
  String _quality = "Highest";
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // Retour en portrait quand on quitte
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _toggleLandscape() {
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    }
    setState(() => _isLandscape = !_isLandscape);
  }

  void _showQualityMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text("Qualité du flux",
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _qualityOption("Highest", "1080p / 4K MAX"),
            _qualityOption("Medium", "720p"),
            _qualityOption("Lowest", "480p / Proxy"),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _qualityOption(String val, String desc) {
    return ListTile(
      leading: Icon(Icons.check,
          color: _quality == val ? Colors.greenAccent : Colors.transparent),
      title: Text(val),
      subtitle: Text(desc, style: const TextStyle(color: Colors.grey)),
      onTap: () {
        setState(() => _quality = val);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── VIDÉO : centrée, 16:9, avec bandes noires en portrait
          Center(
            child: AspectRatio(
              // 16:9 → en portrait, le flux occupera toute la largeur
              // avec des bandes noires en haut/bas (comportement correct)
              aspectRatio: 16 / 9,
              child: NdiNativeView(
                key: ValueKey("${widget.sourceName}_$_quality"),
                sourceName: widget.sourceName,
                quality: _quality,
              ),
            ),
          ),

          // ── BOUTON RETOUR (haut gauche)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 22),
              ),
            ),
          ),

          // ── TITRE SOURCE (haut centre)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.sourceName,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ),
            ),
          ),

          // ── BOUTONS BAS : QUALITÉ + PLEIN ÉCRAN PAYSAGE
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            right: 16,
            child: Column(
              children: [
                // Engrenage → Qualité
                GestureDetector(
                  onTap: _showQualityMenu,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Icon(Icons.settings,
                        color: Colors.white, size: 26),
                  ),
                ),
                // Plein écran paysage 16:9
                GestureDetector(
                  onTap: _toggleLandscape,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isLandscape
                          ? Colors.greenAccent.withOpacity(0.85)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      _isLandscape
                          ? Icons.fullscreen_exit
                          : Icons.stay_current_landscape,
                      color: _isLandscape ? Colors.black : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ÉCRAN TRANSMISSION CAMÉRA NDI
// ─────────────────────────────────────────────
class NdiSendScreen extends StatefulWidget {
  const NdiSendScreen({super.key});

  @override
  State<NdiSendScreen> createState() => _NdiSendScreenState();
}

class _NdiSendScreenState extends State<NdiSendScreen> {
  static const _channel = MethodChannel('com.antigravity/ndi');
  bool _isSending = false;
  String _sourceName = 'MIMO_NDI Camera';

  Future<void> _startSend() async {
    try {
      await _channel.invokeMethod('startSend', {'name': _sourceName});
      if (mounted) setState(() => _isSending = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopSend() async {
    try {
      await _channel.invokeMethod('stopSend');
      if (mounted) setState(() => _isSending = false);
    } catch (e) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    if (_isSending) _stopSend();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Aperçu caméra (native view)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    // Vue caméra (UiKitView dédiée ou placeholder)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam,
                              size: 80,
                              color: _isSending
                                  ? Colors.greenAccent
                                  : Colors.white24),
                          const SizedBox(height: 12),
                          Text(
                            _isSending
                                ? '📡 EN DIRECT — NDI'
                                : 'Caméra prête',
                            style: TextStyle(
                              color: _isSending
                                  ? Colors.greenAccent
                                  : Colors.white38,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Indicateur LIVE
                    if (_isSending)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.circle,
                                  color: Colors.white, size: 10),
                              SizedBox(width: 6),
                              Text('LIVE',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Nom de la source NDI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.label_outline,
                    color: Colors.white38, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Nom NDI de la source',
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                    controller:
                        TextEditingController(text: _sourceName),
                    onChanged: (v) => _sourceName = v,
                    enabled: !_isSending,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Bouton START / STOP
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isSending ? _stopSend : _startSend,
              icon: Icon(_isSending ? Icons.stop_circle : Icons.play_circle),
              label: Text(
                _isSending
                    ? '⏹  Arrêter la diffusion'
                    : '▶  Démarrer la diffusion NDI',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isSending ? Colors.redAccent : Colors.greenAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            _isSending
                ? 'Source visible sur le réseau: "$_sourceName"'
                : 'L\'iPhone diffusera sa caméra en NDI sur le réseau local',
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ÉCRAN MULTIVIEW 4 SOURCES
// ─────────────────────────────────────────────
class MultiviewScreen extends StatefulWidget {
  const MultiviewScreen({super.key});

  @override
  State<MultiviewScreen> createState() => _MultiviewScreenState();
}

class _MultiviewScreenState extends State<MultiviewScreen> {
  static const _channel = MethodChannel('com.antigravity/ndi');
  List<String> _sources = [];
  final List<String?> _slots = [null, null, null, null];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    try {
      final List<dynamic>? result =
          await _channel.invokeMethod('getSources');
      if (mounted) {
        setState(() {
          _sources = result?.cast<String>() ?? [];
        });
      }
    } catch (_) {}
  }

  void _assignSource(int slot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.95),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Source pour écran ${slot + 1}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ..._sources.map((s) => ListTile(
                  leading: const Icon(Icons.sensors,
                      color: Colors.greenAccent),
                  title: Text(s),
                  onTap: () {
                    setState(() => _slots[slot] = s);
                    Navigator.pop(context);
                  },
                )),
            if (_slots[slot] != null)
              ListTile(
                leading: const Icon(Icons.close, color: Colors.redAccent),
                title: const Text('Vider cet écran',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  setState(() => _slots[slot] = null);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _openSlotFullscreen(int slot) {
    final src = _slots[slot];
    if (src == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => NdiPlayerScreen(sourceName: src)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildSlot(0),
                const SizedBox(width: 6),
                _buildSlot(1),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              children: [
                _buildSlot(2),
                const SizedBox(width: 6),
                _buildSlot(3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlot(int index) {
    final source = _slots[index];
    return Expanded(
      child: GestureDetector(
        onTap: () => source != null
            ? _openSlotFullscreen(index)
            : _assignSource(index),
        onLongPress: () => _assignSource(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                // Vidéo ou placeholder
                if (source != null)
                  Positioned.fill(child: NdiNativeView(sourceName: source))
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: Colors.white24, size: 36),
                        const SizedBox(height: 8),
                        Text('Écran ${index + 1}',
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 12)),
                        const Text('Appui long pour\nassigner',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white12, fontSize: 10)),
                      ],
                    ),
                  ),
                // Label source
                if (source != null)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(source,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ),
                  ),
                // Bouton plein écran (haut droite)
                if (source != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _openSlotFullscreen(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.fullscreen,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// VUE NATIVE NDI (UIKitView iOS)
// ─────────────────────────────────────────────
class NdiNativeView extends StatelessWidget {
  final String? sourceName;
  final String? quality; // "Highest", "Medium", "Lowest"
  
  const NdiNativeView({super.key, this.sourceName, this.quality});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return UiKitView(
          viewType: 'ndi-view',
          layoutDirection: TextDirection.ltr,
          creationParams: {
            'name': sourceName,
            'quality': quality ?? "Highest"
          },
          creationParamsCodec: const StandardMessageCodec());
    }
    return const Center(child: Text('Platform not supported'));
  }
}
