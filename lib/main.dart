import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const NdiPlayerApp());
}

class NdiPlayerApp extends StatelessWidget {
  const NdiPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const NdiHomeScreen(),
    );
  }
}

class NdiHomeScreen extends StatefulWidget {
  const NdiHomeScreen({super.key});

  @override
  State<NdiHomeScreen> createState() => _NdiHomeScreenState();
}

class _NdiHomeScreenState extends State<NdiHomeScreen> {
  static const _channel = MethodChannel('com.antigravity/ndi');
  List<String> _sources = [];
  String? _selectedSource;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getSources');
      setState(() {
        _sources = result?.cast<String>() ?? [];
        _isScanning = false;
      });
    } catch (e) {
      debugPrint('Error scanning NDI sources: $e');
      setState(() => _isScanning = false);
    }
  }

  void _selectSource(String source) {
    setState(() {
      _selectedSource = source;
    });
    _channel.invokeMethod('connectToSource', {'name': source});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NDI Real-Time Player'),
        actions: [
          IconButton(
            onPressed: _isScanning ? null : _startScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: _selectedSource == null
                  ? const Center(
                      child: Text(
                        'Select an NDI source to start',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : const NdiNativeView(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 1,
            child: _sources.isEmpty
                ? const Center(child: Text('No NDI sources found'))
                : ListView.builder(
                    itemCount: _sources.length,
                    itemBuilder: (context, index) {
                      final source = _sources[index];
                      final isSelected = _selectedSource == source;
                      return ListTile(
                        leading: Icon(
                          Icons.settings_input_antenna,
                          color: isSelected ? Colors.green : null,
                        ),
                        title: Text(source),
                        selected: isSelected,
                        onTap: () => _selectSource(source),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class NdiNativeView extends StatelessWidget {
  const NdiNativeView({super.key});

  @override
  Widget build(BuildContext context) {
    const String viewType = 'ndi-view';
    const Map<String, dynamic> creationParams = {};

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (Platform.isAndroid) {
      return AndroidView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      return const Center(child: Text('Platform not supported'));
    }
  }
}
