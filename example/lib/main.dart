import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/branded_scanner_screen.dart';
import 'screens/custom_viewfinder_screen.dart';
import 'screens/default_scanner_screen.dart';
import 'screens/image_viewfinder_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const QRExamplesApp());
}

class QRExamplesApp extends StatelessWidget {
  const QRExamplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Lens Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const ExamplesHomeScreen(),
    );
  }
}

class ExamplesHomeScreen extends StatelessWidget {
  const ExamplesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final examples = [
      _ExampleItem(
        title: 'Default Scanner',
        subtitle: 'Basic usage — drop in QrLensScannerPage with no customisation.',
        icon: Icons.qr_code_scanner_rounded,
        color: const Color(0xFF00D4AA),
        page: const DefaultScannerScreen(),
      ),
      _ExampleItem(
        title: 'Custom Viewfinder',
        subtitle: 'viewFinderBuilder: corner brackets, scan line, detect rect, '
            'capture & result state transitions, plus a local AnimationController.',
        icon: Icons.crop_free_rounded,
        color: const Color(0xFF6C63FF),
        page: const CustomViewfinderScreen(),
      ),
      _ExampleItem(
        title: 'Branded Scanner',
        subtitle: 'Custom appBarBuilder + resultBuilder + minimal rounded overlay '
            'with a brand accent colour.',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFFF6B6B),
        page: const BrandedScannerScreen(),
      ),
      _ExampleItem(
        title: 'Image / Widget Viewfinder',
        subtitle: 'Place any widget (image, SVG, icon) over boundingRect with '
            'ScaleTransition pulse. Uses autoResume: false and a controller '
            'to resume scanning after a custom result dialog.',
        icon: Icons.image_outlined,
        color: const Color(0xFFFFB347),
        page: const ImageViewfinderScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'QR Lens Examples',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: examples.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _ExampleCard(item: examples[i]),
      ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────────────────────

class _ExampleItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget page;

  const _ExampleItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.page,
  });
}

class _ExampleCard extends StatelessWidget {
  final _ExampleItem item;

  const _ExampleCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.page)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.white30),
          ],
        ),
      ),
    );
  }
}
