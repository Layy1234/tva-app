import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _cleanOldData();
  } catch (e) {
    print('Error cleaning old data: $e');
  }
  runApp(const MyApp());
}

Future<void> _cleanOldData() async {
  final stores = await DatabaseHelper.instance.getAllStores();
  final now = DateTime.now();
  for (var store in stores) {
    if (store['createdAt'] != null) {
      final createdAt = DateTime.tryParse(store['createdAt']);
      if (createdAt != null) {
        final diff = now.difference(createdAt).inDays;
        if (diff >= 30) {
          await DatabaseHelper.instance.deleteStore(store['id']);
          List<String> imagePaths = [];
          if (store['imagePaths'] != null && store['imagePaths'].toString().isNotEmpty) {
            try { imagePaths = List<String>.from(jsonDecode(store['imagePaths'])); } catch (e) {}
          } else if (store['imagePath'] != null && store['imagePath'].toString().isNotEmpty) {
            imagePaths = [store['imagePath']];
          }
          for (String path in imagePaths) {
            try {
              final file = File(path);
              if (file.existsSync()) file.deleteSync();
            } catch (e) {}
          }
        }
      }
    }
  }
}

bool _isGeneratingPdfGlobal = false;

Future<void> generateAndPrintPdf(BuildContext context, List<Map<String, dynamic>> dataList) async {
  if (_isGeneratingPdfGlobal) return;
  _isGeneratingPdfGlobal = true;
  
  try {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      return const Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.deepOrange),
              SizedBox(height: 16),
              Text('Menyiapkan Pratinjau PDF...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    },
  );

  final pdf = pw.Document();
  final prefs = await SharedPreferences.getInstance();
  final userName = prefs.getString('userName') ?? 'Tidak Ada Nama';

  // Dapatkan semua path unik
  Set<String> uniquePaths = {};
  for (var data in dataList) {
    List<String> paths = [];
    if (data['imagePaths'] != null && data['imagePaths'].toString().isNotEmpty) {
      try { paths = List<String>.from(jsonDecode(data['imagePaths'])); } catch(e){}
    } else if (data['imagePath'] != null && data['imagePath'].toString().isNotEmpty) {
      paths = [data['imagePath']];
    }
    uniquePaths.addAll(paths);
  }

  Map<String, pw.ImageProvider> preloadedImages = {};

  // Memuat semua foto secara bersamaan (paralel) agar tidak lama
  await Future.wait(uniquePaths.map((path) async {
    try {
      final imageFile = File(path);
      if (imageFile.existsSync()) {
        preloadedImages[path] = await flutterImageProvider(
          ResizeImage(FileImage(imageFile), width: 800),
        );
      }
    } catch (e) {
      print("Error loading image $path: $e");
    }
  }));

  if (context.mounted) Navigator.pop(context);

  for (int i = 0; i < dataList.length; i++) {
    final data = dataList[i];
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          List<pw.Widget> elements = [];
          
          List<pw.ImageProvider> pdfImages = [];
          List<String> imagePaths = [];
          if (data['imagePaths'] != null && data['imagePaths'].toString().isNotEmpty) {
            try { imagePaths = List<String>.from(jsonDecode(data['imagePaths'])); } catch(e){}
          } else if (data['imagePath'] != null && data['imagePath'].toString().isNotEmpty) {
            imagePaths = [data['imagePath']];
          }

          for (String path in imagePaths) {
            if (preloadedImages.containsKey(path)) {
              pdfImages.add(preloadedImages[path]!);
            }
          }

          elements.add(
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Laporan Visit Toko Vape', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                  pw.Text(
                    '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} - ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                    style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
          );
          
          // NAMA SESUAI YANG INPUT
          elements.add(pw.Container(
            alignment: pw.Alignment.centerLeft,
            margin: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Text('Dilaporkan oleh: $userName', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
          ));

          elements.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Informasi Toko', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Divider(color: PdfColors.grey400),
                        pw.SizedBox(height: 4),
                        pw.Row(children: [
                          pw.Expanded(child: pw.Text('Nama Toko:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                          pw.Expanded(flex: 2, child: pw.Text('${data['storeName'] ?? '-'}', style: const pw.TextStyle(fontSize: 12))),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.Expanded(child: pw.Text('PIC:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                          pw.Expanded(flex: 2, child: pw.Text('${data['picName'] ?? '-'}', style: const pw.TextStyle(fontSize: 12))),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.Expanded(child: pw.Text('No. HP:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                          pw.Expanded(flex: 2, child: pw.Text('${data['phone'] ?? '-'}', style: const pw.TextStyle(fontSize: 12))),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.Expanded(child: pw.Text('Alamat:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                          pw.Expanded(flex: 2, child: pw.Text('${data['address'] ?? '-'}', style: const pw.TextStyle(fontSize: 12))),
                        ]),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(color: PdfColors.orange50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Data Produk / Inventory', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Divider(color: PdfColors.orange200),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('Liquid', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('VOLX: ${data['volx'] != null && data['volx'].toString().isNotEmpty ? data['volx'] : '-'}', style: pw.TextStyle(fontSize: 12)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('TAKIS: ${data['takis'] != null && data['takis'].toString().isNotEmpty ? data['takis'] : '-'}', style: pw.TextStyle(fontSize: 12)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('TRIBE: ${data['tribe'] != null && data['tribe'].toString().isNotEmpty ? data['tribe'] : '-'}', style: pw.TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('Pod', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('VOLX: ${data['pod_volx'] != null && data['pod_volx'].toString().isNotEmpty ? data['pod_volx'] : '-'}', style: pw.TextStyle(fontSize: 12)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('TAKIS: ${data['pod_takis'] != null && data['pod_takis'].toString().isNotEmpty ? data['pod_takis'] : '-'}', style: pw.TextStyle(fontSize: 12)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('TRIBE: ${data['pod_tribe'] != null && data['pod_tribe'].toString().isNotEmpty ? data['pod_tribe'] : '-'}', style: pw.TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        pw.Divider(color: PdfColors.orange200),
                        pw.SizedBox(height: 4),
                        
                        // CT Paling Bawah
                        pw.Text('CT: ${data['ct'] != null && data['ct'].toString().isNotEmpty ? data['ct'] : '-'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          elements.add(pw.SizedBox(height: 12));

          elements.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              width: double.infinity,
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('INSIDE :', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 4),
                  pw.Text('${data['inside'] ?? '-'}', style: const pw.TextStyle(fontSize: 12, lineSpacing: 2)),
                ],
              ),
            )
          );
          elements.add(pw.SizedBox(height: 16));

          if (pdfImages.isNotEmpty) {
            elements.add(pw.Text('Lampiran Foto', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));
            elements.add(pw.SizedBox(height: 8));
            elements.add(
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pdfImages.map((img) => pw.Container(
                  height: 150,
                  width: 150,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 2), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                  child: pw.ClipRRect(horizontalRadius: 6, verticalRadius: 6, child: pw.Image(img, fit: pw.BoxFit.cover)),
                )).toList(),
              )
            );
          }

          return elements;
        },
      ),
    );
  }

  final now = DateTime.now();
  final List<String> monthNames = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];
  final dateStr = '${now.day} ${monthNames[now.month]}';
  final userNameSanitized = userName.replaceAll(' ', '_');
  final title = 'Laporan_Tanggal ${dateStr}_$userNameSanitized';
  
  await Printing.layoutPdf(
    name: '$title.pdf',
    onLayout: (PdfPageFormat format) async => pdf.save(),
  );
  
  } finally {
    _isGeneratingPdfGlobal = false;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TVA App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, primary: Colors.deepOrange, secondary: Colors.orange),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.orange.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.deepOrange, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkUserName();
  }

  Future<void> _checkUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('userName');
    if (name == null || name.isEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WelcomePage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DataFormPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _nameCtrl = TextEditingController();
  bool _isLoading = false;

  void _submit() async {
    final name = _nameCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama lengkap tidak boleh kosong')));
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DataFormPage()));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selamat Datang!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Terjadi kesalahan: $e')));
      }
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_circle, size: 80, color: Colors.deepOrange),
              const SizedBox(height: 24),
              const Text(
                'Selamat Datang!',
                textAlign: TextAlign.center, 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 8),
              const Text(
                'Silakan masukkan Nama Lengkap Anda untuk mulai menggunakan aplikasi.',
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.grey)
              ),
              const SizedBox(height: 32),
              
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Lengkap', prefixIcon: Icon(Icons.person)),
              ),
              
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                child: _isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Mulai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class DataFormPage extends StatefulWidget {
  final Map<String, dynamic>? storeData;
  const DataFormPage({super.key, this.storeData});

  @override
  State<DataFormPage> createState() => _DataFormPageState();
}

class _DataFormPageState extends State<DataFormPage> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _storeNameCtrl = TextEditingController();
  final TextEditingController _ownerNameCtrl = TextEditingController();
  final TextEditingController _picNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  
  final TextEditingController _volxCtrl = TextEditingController(); // Liquid Volx
  final TextEditingController _takisCtrl = TextEditingController(); // Liquid Takis
  final TextEditingController _tribeCtrl = TextEditingController(); // Liquid Tribe
  
  final TextEditingController _podVolxCtrl = TextEditingController();
  final TextEditingController _podTakisCtrl = TextEditingController();
  final TextEditingController _podTribeCtrl = TextEditingController();
  
  final TextEditingController _ctCtrl = TextEditingController();
  final TextEditingController _insideCtrl = TextEditingController();

  List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  
  List<Map<String, dynamic>> _localStores = [];

  Future<void> _loadLocalStores() async {
    final stores = await DatabaseHelper.instance.getAllStores();
    if (mounted) {
      setState(() {
        _localStores = stores;
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    _loadLocalStores();
    if (widget.storeData != null) {
      _storeNameCtrl.text = widget.storeData!['storeName']?.toString() ?? '';
      _ownerNameCtrl.text = widget.storeData!['ownerName']?.toString() ?? '';
      _picNameCtrl.text = widget.storeData!['picName']?.toString() ?? '';
      _phoneCtrl.text = widget.storeData!['phone']?.toString() ?? '';
      _addressCtrl.text = widget.storeData!['address']?.toString() ?? '';
      
      _volxCtrl.text = widget.storeData!['volx']?.toString() ?? '';
      _takisCtrl.text = widget.storeData!['takis']?.toString() ?? '';
      _tribeCtrl.text = widget.storeData!['tribe']?.toString() ?? '';
      
      _podVolxCtrl.text = widget.storeData!['pod_volx']?.toString() ?? '';
      _podTakisCtrl.text = widget.storeData!['pod_takis']?.toString() ?? '';
      _podTribeCtrl.text = widget.storeData!['pod_tribe']?.toString() ?? '';
      
      _ctCtrl.text = widget.storeData!['ct']?.toString() ?? '';
      _insideCtrl.text = widget.storeData!['inside']?.toString() ?? '';
      
      List<String> imagePaths = [];
      if (widget.storeData!['imagePaths'] != null && widget.storeData!['imagePaths'].toString().isNotEmpty) {
        try { imagePaths = List<String>.from(jsonDecode(widget.storeData!['imagePaths'])); } catch(e){}
      }
      for (String p in imagePaths) {
        final f = File(p);
        if (f.existsSync()) _images.add(f);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        setState(() { _images.addAll(pickedFiles.map((e) => File(e.path))); });
      }
    } else {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() { _images.add(File(pickedFile.path)); });
      }
    }
  }

  Future<Map<String, dynamic>> _getFormDataAsync() async {
    List<String> savedPaths = [];
    final dir = await getApplicationDocumentsDirectory();
    for (File img in _images) {
      if (img.path.contains(dir.path)) {
        savedPaths.add(img.path);
      } else {
        final fileName = DateTime.now().millisecondsSinceEpoch.toString() + '_' + img.path.split('/').last;
        final savedImage = await img.copy('${dir.path}/$fileName');
        savedPaths.add(savedImage.path);
      }
    }

    return {
      'storeName': _storeNameCtrl.text,
      'ownerName': _ownerNameCtrl.text,
      'picName': _picNameCtrl.text,
      'phone': _phoneCtrl.text,
      'address': _addressCtrl.text,
      'volx': _volxCtrl.text,
      'takis': _takisCtrl.text,
      'tribe': _tribeCtrl.text,
      'pod_volx': _podVolxCtrl.text,
      'pod_takis': _podTakisCtrl.text,
      'pod_tribe': _podTribeCtrl.text,
      'ct': _ctCtrl.text,
      'inside': _insideCtrl.text,
      'imagePaths': jsonEncode(savedPaths),
    };
  }

  void _clearForm() {
    _formKey.currentState!.reset();
    _storeNameCtrl.clear();
    _ownerNameCtrl.clear();
    _picNameCtrl.clear();
    _phoneCtrl.clear();
    _addressCtrl.clear();
    _volxCtrl.clear();
    _takisCtrl.clear();
    _tribeCtrl.clear();
    _podVolxCtrl.clear();
    _podTakisCtrl.clear();
    _podTribeCtrl.clear();
    _ctCtrl.clear();
    _insideCtrl.clear();
    setState(() { _images.clear(); });
  }

  Future<void> _processSave({required bool printPdf}) async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Mohon lengkapi semua field yang wajib diisi (*)!'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);

    final data = await _getFormDataAsync();
    if (widget.storeData != null) {
      data['id'] = widget.storeData!['id'];
      await DatabaseHelper.instance.updateStore(data);
    } else {
      await DatabaseHelper.instance.insertStore(data);
    }
    
    setState(() => _isLoading = false);

    if (printPdf) {
      await generateAndPrintPdf(context, [data]);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(printPdf ? '✅ PDF berhasil dibuat!' : '✅ Data berhasil disimpan ke Lokal!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (widget.storeData != null) {
        Navigator.pop(context, true);
      } else {
        _clearForm();
      }
    }
  }

  void _showImagePreview(File img) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(child: Image.file(img, fit: BoxFit.contain)),
            Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)))
          ],
        )
      )
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.storeData != null ? 'Edit Laporan' : 'Laporan Visit', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        // actions dihapus agar otomatis muncul hamburger icon untuk endDrawer
      ),
      endDrawer: widget.storeData == null ? Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.deepOrange),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.account_circle, color: Colors.white, size: 48),
                  SizedBox(height: 8),
                  Text('Menu Utama', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history_edu, color: Colors.deepOrange),
              title: const Text('Riwayat Laporan'),
              onTap: () {
                Navigator.pop(context); // Tutup drawer
                Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.deepOrange),
              title: const Text('Ganti Nama'),
              onTap: () async {
                Navigator.pop(context); // Tutup drawer
                final prefs = await SharedPreferences.getInstance();
                final currentName = prefs.getString('userName') ?? '';
                final TextEditingController nameCtrl = TextEditingController(text: currentName);
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Ganti Nama Pengguna'),
                      content: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                        ElevatedButton(
                          onPressed: () async {
                            if (nameCtrl.text.trim().isNotEmpty) {
                              await prefs.setString('userName', nameCtrl.text.trim());
                              if (mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama berhasil diperbarui')));
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                          child: const Text('Simpan'),
                        )
                      ],
                    ),
                  );
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context); // Tutup drawer
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('userName');
                if (mounted) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WelcomePage()));
                }
              },
            ),
          ],
        ),
      ) : null,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Informasi Toko', Icons.storefront),
                          Autocomplete<Map<String, dynamic>>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<Map<String, dynamic>>.empty();
                              }
                              return _localStores.where((store) {
                                final name = (store['storeName'] ?? '').toString().toLowerCase();
                                return name.contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            displayStringForOption: (Map<String, dynamic> option) => option['storeName'] ?? '',
                            onSelected: (Map<String, dynamic> selection) {
                              _storeNameCtrl.text = selection['storeName']?.toString() ?? '';
                              _ownerNameCtrl.text = selection['ownerName']?.toString() ?? '';
                              _picNameCtrl.text = selection['picName']?.toString() ?? '';
                              _phoneCtrl.text = selection['phone']?.toString() ?? '';
                              _addressCtrl.text = selection['address']?.toString() ?? '';
                              _volxCtrl.text = selection['volx']?.toString() ?? '';
                              _takisCtrl.text = selection['takis']?.toString() ?? '';
                              _tribeCtrl.text = selection['tribe']?.toString() ?? '';
                              _podVolxCtrl.text = selection['pod_volx']?.toString() ?? '';
                              _podTakisCtrl.text = selection['pod_takis']?.toString() ?? '';
                              _podTribeCtrl.text = selection['pod_tribe']?.toString() ?? '';
                              _ctCtrl.text = selection['ct']?.toString() ?? '';
                              _insideCtrl.text = selection['inside']?.toString() ?? '';
                              // Trigger UI update if needed
                              setState(() {});
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              if (_storeNameCtrl.text.isNotEmpty && fieldTextEditingController.text.isEmpty) {
                                fieldTextEditingController.text = _storeNameCtrl.text;
                              }
                              return TextFormField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: const InputDecoration(labelText: 'Nama Vape Store *', prefixIcon: Icon(Icons.store)),
                                validator: (value) => value == null || value.trim().isEmpty ? 'Nama toko harus diisi' : null,
                                onChanged: (val) {
                                  _storeNameCtrl.text = val;
                                }
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _ownerNameCtrl, decoration: const InputDecoration(labelText: 'Nama Owner *', prefixIcon: Icon(Icons.person)), validator: (value) => value == null || value.trim().isEmpty ? 'Wajib diisi' : null)),
                              const SizedBox(width: 12),
                              Expanded(child: TextFormField(controller: _picNameCtrl, decoration: const InputDecoration(labelText: 'Nama PIC *', prefixIcon: Icon(Icons.badge)), validator: (value) => value == null || value.trim().isEmpty ? 'Wajib diisi' : null)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor HP *', prefixIcon: Icon(Icons.phone)), validator: (value) => value == null || value.trim().isEmpty ? 'Wajib diisi' : null),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Alamat Toko Lengkap *', prefixIcon: Icon(Icons.location_on)), maxLines: 2,
                            validator: (value) => value == null || value.trim().isEmpty ? 'Alamat harus diisi' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Data Inventory / Status', Icons.inventory),
                          
                          // LIQUID
                          const Text('Liquid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _volxCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Liquid VOLX'))),
                              const SizedBox(width: 12),
                              Expanded(child: TextFormField(controller: _takisCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Liquid TAKIS'))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _tribeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Liquid TRIBE'))),
                              const SizedBox(width: 12),
                              const Spacer(),
                            ],
                          ),
                          
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Divider(),
                          ),

                          // POD
                          const Text('Pod', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _podVolxCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pod VOLX'))),
                              const SizedBox(width: 12),
                              Expanded(child: TextFormField(controller: _podTakisCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pod TAKIS'))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _podTribeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pod TRIBE'))),
                              const SizedBox(width: 12),
                              const Spacer(),
                            ],
                          ),

                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Divider(),
                          ),
                          
                          // CT (Paling Bawah)
                          const Text('CT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _ctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'CT'))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Inside & Dokumentasi', Icons.analytics),
                          TextFormField(controller: _insideCtrl, decoration: const InputDecoration(labelText: 'Ringkasan / Apa yang didapat (Inside)', alignLabelWithHint: true), maxLines: 4),
                          const SizedBox(height: 20),
                          
                          Text('Foto Dokumentasi (Bisa lebih dari 1)', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          if (_images.isNotEmpty)
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: _images.map((img) => Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => _showImagePreview(img),
                                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(img, height: 120, width: 120, fit: BoxFit.cover)),
                                  ),
                                  Positioned(
                                    top: 4, right: 4,
                                    child: InkWell(
                                      onTap: () { setState(() { _images.remove(img); }); },
                                      child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 16)),
                                    ),
                                  )
                                ]
                              )).toList(),
                            )
                          else
                            Container(
                              height: 120, width: double.infinity,
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
                              child: Center(child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey.shade400)),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.camera_alt), label: const Text('Kamera'), onPressed: () => _pickImage(ImageSource.camera))),
                              const SizedBox(width: 12),
                              Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.photo_library), label: const Text('Galeri'), onPressed: () => _pickImage(ImageSource.gallery))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('SIMPAN & GENERATE PDF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: _isLoading ? null : () => _processSave(printPdf: true),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: _isLoading ? null : () => _processSave(printPdf: false),
                    child: Text(widget.storeData != null ? 'Update Saja' : 'Simpan ke Riwayat Saja', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Menyimpan Data...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _stores = [];
  Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _refreshStores();
  }

  Future<void> _refreshStores() async {
    final data = await DatabaseHelper.instance.getAllStores();
    setState(() {
      _stores = data;
      _selectedIds.removeWhere((id) => !data.any((store) => store['id'] == id));
    });
  }

  Future<void> _deleteStore(int id) async {
    await DatabaseHelper.instance.deleteStore(id);
    _refreshStores();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data berhasil dihapus')));
  }

  void _showReorderDialog() {
    final selectedData = _stores.where((s) => _selectedIds.contains(s['id'])).toList();
    List<Map<String, dynamic>> reorderedData = List.from(selectedData);
    
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setStateBuilder) {
            return AlertDialog(
              title: const Text('Urutkan Laporan'),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) {
                    setStateBuilder(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = reorderedData.removeAt(oldIndex);
                      reorderedData.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (int i = 0; i < reorderedData.length; i++)
                      ListTile(
                        key: ValueKey(reorderedData[i]['id']),
                        leading: const Icon(Icons.drag_handle),
                        title: Text(reorderedData[i]['storeName']),
                        subtitle: Text(reorderedData[i]['ownerName']),
                      )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    generateAndPrintPdf(context, reorderedData);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                  child: const Text('Buat PDF'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Riwayat Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0,
        actions: [
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: Text('Cetak (${_selectedIds.length})'),
                onPressed: () {
                  if (_selectedIds.length > 1) {
                    _showReorderDialog();
                  } else {
                    final selectedData = _stores.where((s) => _selectedIds.contains(s['id'])).toList();
                    generateAndPrintPdf(context, selectedData);
                  }
                },
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStores,
        child: _stores.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off, size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text('Belum ada data toko', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _stores.length,
                itemBuilder: (context, index) {
                final store = _stores[index];
                return Card(
                  elevation: 0, margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _selectedIds.contains(store['id']),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) { _selectedIds.add(store['id']); } else { _selectedIds.remove(store['id']); }
                            });
                          },
                        ),
                        if (store['imagePaths'] != null && store['imagePaths'].toString().isNotEmpty && store['imagePaths'] != '[]')
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: Builder(builder: (context) {
                            try {
                              final paths = List<String>.from(jsonDecode(store['imagePaths']));
                              if (paths.isNotEmpty) {
                                return Image.file(File(paths.first), width: 50, height: 50, fit: BoxFit.cover);
                              }
                            } catch(e) {}
                            return CircleAvatar(backgroundColor: Colors.blue.shade100, child: const Icon(Icons.store, color: Colors.blue));
                          }))
                        else
                          CircleAvatar(backgroundColor: Colors.blue.shade100, child: const Icon(Icons.store, color: Colors.blue)),
                      ],
                    ),
                    title: Text(store['storeName'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(store['address'] ?? 'No Address', maxLines: 1, overflow: TextOverflow.ellipsis),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0), width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Owner: ${store['ownerName']} | PIC: ${store['picName']}'),
                            const Divider(),
                            const Text('Liquid:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('VOLX: ${store['volx']} | TAKIS: ${store['takis']} | TRIBE: ${store['tribe']}'),
                            const SizedBox(height: 4),
                            const Text('Pod:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('VOLX: ${store['pod_volx']} | TAKIS: ${store['pod_takis']} | TRIBE: ${store['pod_tribe']}'),
                            const SizedBox(height: 4),
                            Text('CT: ${store['ct']}'),
                            const Divider(),
                            const Text('INSIDE:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('${store['inside']}', style: const TextStyle(fontStyle: FontStyle.italic)),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.edit, color: Colors.blue), label: const Text('Edit', style: TextStyle(color: Colors.blue)),
                                  onPressed: () async {
                                    final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => DataFormPage(storeData: store)));
                                    if (res == true) _refreshStores();
                                  },
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red), label: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Hapus Data'),
                                        content: const Text('Yakin ingin menghapus data ini?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                          TextButton(
                                            onPressed: () { Navigator.pop(ctx); _deleteStore(store['id']); },
                                            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}
