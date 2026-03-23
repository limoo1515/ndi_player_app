import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

void main() {
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

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _pages = [
    const NdiReceiveScreen(),
    const Center(child: Text("Transmettre Caméra (Bientôt disponible)", style: TextStyle(fontSize: 20))),
    const Center(child: Text("Multiview 4 (Bientôt disponible)", style: TextStyle(fontSize: 20))),
  ];

  final List<String> _titles = ["Réception Flux", "Transmission Caméra", "Multiview 4"];

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
          title: Text(_titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                colorFilter: ColorFilter.mode(Colors.black38, BlendMode.darken),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: AssetImage('IMG_0730.JPG'),
                ),
                SizedBox(height: 10),
                Text('MIMO_NDI', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                Text('Professional Broadcast', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          _drawerItem(0, Icons.download, 'Recevoir Flux'),
          _drawerItem(1, Icons.videocam, 'Envoyer Caméra'),
          _drawerItem(2, Icons.grid_view, 'Multiview 4'),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white70),
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
      leading: Icon(icon, color: isSelected ? Colors.greenAccent : Colors.white70),
      title: Text(title, style: TextStyle(color: isSelected ? Colors.greenAccent : Colors.white)),
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }
}

class NdiReceiveScreen extends StatefulWidget {
  const NdiReceiveScreen({super.key});

  @override
  State<NdiReceiveScreen> createState() => _NdiReceiveScreenState();
}

class _NdiReceiveScreenState extends State<NdiReceiveScreen> {
  static const _channel = MethodChannel('com.antigravity/ndi');
  List<String> _sources = [];
  String? _selectedSource;
  bool _isScanning = false;
  String _quality = "Highest";

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getSources');
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

  void _selectSource(String source) {
    setState(() {
      _selectedSource = source;
    });
    _channel.invokeMethod('connectToSource', {
      'name': source,
      'bandwidth': _quality == "Highest" ? 100 : (_quality == "Medium" ? 50 : 0),
    });
  }

  void _showQualityMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text("Sélectionner la Qualité", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _qualityOption("Highest", "1080p / 4K"),
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
      leading: Icon(Icons.check, color: _quality == val ? Colors.green : Colors.transparent),
      title: Text(val),
      subtitle: Text(desc, style: const TextStyle(color: Colors.grey)),
      onTap: () {
        setState(() => _quality = val);
        Navigator.pop(context);
        if (_selectedSource != null) _selectSource(_selectedSource!);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                ),
                child: Stack(
                  children: [
                    _selectedSource == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset('IMG_0730.JPG', width: 200, opacity: const AlwaysStoppedAnimation(0.2)),
                                const SizedBox(height: 20),
                                const Text('Sélectionnez un flux NDI', style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                          )
                        : const NdiNativeView(),
                    if (_selectedSource != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: CircleAvatar(
                          backgroundColor: Colors.black45,
                          child: IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white),
                            onPressed: _showQualityMenu,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SOURCES DISPONIBLES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white54)),
              IconButton(onPressed: _isScanning ? null : _startScan, icon: const Icon(Icons.refresh, size: 20)),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        Expanded(
          flex: 1,
          child: _sources.isEmpty
              ? const Center(child: Text('Recherche de sources...'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _sources.length,
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    final isSelected = _selectedSource == source;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            color: isSelected ? Colors.greenAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                            child: ListTile(
                              leading: Icon(Icons.sensors, color: isSelected ? Colors.greenAccent : Colors.white38),
                              title: Text(source, style: TextStyle(color: isSelected ? Colors.greenAccent : Colors.white)),
                              onTap: () => _selectSource(source),
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

class NdiNativeView extends StatelessWidget {
  const NdiNativeView({super.key});

  @override
  Widget build(BuildContext context) {
    const String viewType = 'ndi-view';
    if (Platform.isIOS) {
      return const UiKitView(viewType: viewType, layoutDirection: TextDirection.ltr, creationParamsCodec: StandardMessageCodec());
    } else {
      return const Center(child: Text('Platform not supported'));
    }
  }
}
