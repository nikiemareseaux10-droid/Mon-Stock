import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

const Color kVert = Color(0xFF176B50);
const Color kVertFonce = Color(0xFF142B25);

/// Pont JavaScript injecté après le chargement de la page.
/// Il remplace les fonctions du navigateur qui n'existent pas dans une
/// application Android : téléchargement de fichiers, ouverture d'une fenêtre
/// d'impression (factures, bons de commande, étiquettes) et window.print().
const String kBridgeJs = r'''
(function () {
  if (window.__msBridge) return;
  window.__msBridge = true;

  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    return window.flutter_inappwebview.callHandler.apply(
      window.flutter_inappwebview, [name].concat(args));
  }

  // Sauvegardes JSON et exports CSV
  window.downloadBlob = function (blob, name) {
    var reader = new FileReader();
    reader.onloadend = function () {
      var s = String(reader.result || '');
      var i = s.indexOf(',');
      call('saveFile', name || 'fichier', i >= 0 ? s.substring(i + 1) : '');
    };
    reader.readAsDataURL(blob);
  };

  // Factures, bons de commande, étiquettes : window.open + document.write
  window.open = function () {
    var buf = '';
    return {
      document: {
        write: function (h) { buf += h; },
        writeln: function (h) { buf += h + '\n'; },
        close: function () { call('printHtml', buf); }
      },
      focus: function () {},
      close: function () {},
      print: function () {}
    };
  };

  // Bouton « Imprimer » des rapports
  window.print = function () { call('printPage'); };
})();
''';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kVertFonce,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MonStockApp());
}

class MonStockApp extends StatelessWidget {
  const MonStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mon Stock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kVert),
      ),
      home: const MonStockPage(),
    );
  }
}

class MonStockPage extends StatefulWidget {
  const MonStockPage({super.key});

  @override
  State<MonStockPage> createState() => _MonStockPageState();
}

class _MonStockPageState extends State<MonStockPage> {
  InAppWebViewController? _web;
  bool _loading = true;

  // ---------------------------------------------------------------- fichiers

  String _nomSur(String nom) {
    final propre = nom.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return propre.isEmpty ? 'mon-stock-sauvegarde.json' : propre;
  }

  String _mime(String nom) {
    final n = nom.toLowerCase();
    if (n.endsWith('.json')) return 'application/json';
    if (n.endsWith('.csv')) return 'text/csv';
    return 'application/octet-stream';
  }

  Future<void> _enregistrer(String nom, String base64Data) async {
    try {
      final fichierNom = _nomSur(nom);
      final dossier = await getTemporaryDirectory();
      final fichier = File('${dossier.path}/$fichierNom');
      await fichier.writeAsBytes(base64Decode(base64Data), flush: true);
      await Share.shareXFiles(
        [XFile(fichier.path, mimeType: _mime(fichierNom))],
        subject: fichierNom,
      );
    } catch (e) {
      _message('Impossible d\'enregistrer le fichier : $e');
    }
  }

  Future<void> _imprimerHtml(String html) async {
    try {
      // On retire les scripts (window.print) : l'impression est gérée ici.
      final propre = html.replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        '',
      );
      await Printing.layoutPdf(
        name: 'Mon Stock',
        onLayout: (format) => Printing.convertHtml(format: format, html: propre),
      );
    } catch (e) {
      _message('Impression impossible : $e');
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texte)));
  }

  // --------------------------------------------------------------- dialogues
  // Sans ces fonctions, alert(), confirm() et prompt() ne s'affichent pas
  // dans la WebView (et confirm() répondrait « non » à chaque suppression).

  Future<void> _alerte(String texte) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Text(texte),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmer(String texte) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Text(texte),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<String?> _saisir(String texte, String? defaut) async {
    final champ = TextEditingController(text: defaut ?? '');
    final r = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(texte),
            const SizedBox(height: 12),
            TextField(controller: champ, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, champ.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    champ.dispose();
    return r;
  }

  Future<bool> _confirmerQuitter() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: const Text('Quitter Mon Stock ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Oui'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  // ------------------------------------------------------------------- ecran

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final web = _web;
        if (web != null && await web.canGoBack()) {
          await web.goBack();
          return;
        }
        if (await _confirmerQuitter()) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: kVertFonce,
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialFile: 'assets/index.html',
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  allowFileAccess: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  mediaPlaybackRequiresUserGesture: false,
                  supportZoom: false,
                  textZoom: 100,
                ),
                onWebViewCreated: (controller) {
                  _web = controller;

                  controller.addJavaScriptHandler(
                    handlerName: 'saveFile',
                    callback: (args) async {
                      if (args.length >= 2) {
                        await _enregistrer(args[0].toString(), args[1].toString());
                      }
                      return true;
                    },
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'printHtml',
                    callback: (args) async {
                      if (args.isNotEmpty) {
                        await _imprimerHtml(args[0].toString());
                      }
                      return true;
                    },
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'printPage',
                    callback: (args) async {
                      await controller.printCurrentPage();
                      return true;
                    },
                  );
                },
                onLoadStop: (controller, url) async {
                  await controller.evaluateJavascript(source: kBridgeJs);
                  if (mounted && _loading) setState(() => _loading = false);
                },
                onJsAlert: (controller, request) async {
                  await _alerte(request.message ?? '');
                  return JsAlertResponse(
                    handledByClient: true,
                    action: JsAlertResponseAction.CONFIRM,
                  );
                },
                onJsConfirm: (controller, request) async {
                  final ok = await _confirmer(request.message ?? '');
                  return JsConfirmResponse(
                    handledByClient: true,
                    action: ok
                        ? JsConfirmResponseAction.CONFIRM
                        : JsConfirmResponseAction.CANCEL,
                  );
                },
                onJsPrompt: (controller, request) async {
                  final valeur =
                      await _saisir(request.message ?? '', request.defaultValue);
                  return JsPromptResponse(
                    handledByClient: true,
                    value: valeur,
                    action: valeur == null
                        ? JsPromptResponseAction.CANCEL
                        : JsPromptResponseAction.CONFIRM,
                  );
                },
                onPermissionRequest: (controller, request) async {
                  // Caméra du scanner de codes-barres
                  final etat = await Permission.camera.request();
                  return PermissionResponse(
                    resources: request.resources,
                    action: etat.isGranted
                        ? PermissionResponseAction.GRANT
                        : PermissionResponseAction.DENY,
                  );
                },
              ),
              if (_loading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: kVertFonce,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
