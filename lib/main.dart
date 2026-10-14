import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:anbarban/number_parser.dart';
import 'package:anbarban/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const green = Color(0xFF176B55);
const bg = Color(0xFFF5F7F6);

String money(dynamic value) {
  final n = (value as num?) ?? 0;
  return formatMoney(n);
}

String number(dynamic value) {
  final n = (value as num?) ?? 0;
  return formatNumber(n);
}

String dateText(String? value) {
  if (value == null) return '—';
  final d = DateTime.tryParse(value)?.toLocal();
  if (d == null) return value;
  return fa('${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}');
}

class InventoryDb {
  InventoryDb._();
  static final InventoryDb instance = InventoryDb._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'anbarban.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sku TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT '',
            buy_price REAL NOT NULL DEFAULT 0,
            sell_price REAL NOT NULL DEFAULT 0,
            quantity REAL NOT NULL DEFAULT 0,
            min_quantity REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE movements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER,
            product_name TEXT NOT NULL,
            type TEXT NOT NULL,
            quantity REAL NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Map<String, dynamic>>> products() async {
    final db = await database;
    return db.query('products', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<List<Map<String, dynamic>>> movements() async {
    final db = await database;
    return db.query('movements', orderBy: 'id DESC', limit: 500);
  }

  Future<Map<String, double>> movementTotals() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'in' THEN quantity ELSE 0 END), 0)
          AS total_in,
        COALESCE(SUM(CASE WHEN type = 'out' THEN quantity ELSE 0 END), 0)
          AS total_out
      FROM movements
    ''');

    final row = rows.first;
    return {
      'in': (row['total_in'] as num).toDouble(),
      'out': (row['total_out'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> movementTotalsForDay(DateTime day) async {
    final db = await database;
    final date = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';

    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'in' THEN quantity ELSE 0 END), 0)
          AS total_in,
        COALESCE(SUM(CASE WHEN type = 'out' THEN quantity ELSE 0 END), 0)
          AS total_out
      FROM movements
      WHERE substr(created_at, 1, 10) = ?
    ''', [date]);

    final row = rows.first;
    return {
      'in': (row['total_in'] as num).toDouble(),
      'out': (row['total_out'] as num).toDouble(),
    };
  }

  Future<void> saveProduct(Map<String, dynamic> data, {int? id}) async {
    final db = await database;
    if (id != null) {
      await db.update('products', {
        'name': data['name'],
        'sku': data['sku'],
        'category': data['category'],
        'buy_price': data['buy_price'],
        'sell_price': data['sell_price'],
        'min_quantity': data['min_quantity'],
      }, where: 'id = ?', whereArgs: [id]);
      return;
    }

    await db.transaction((txn) async {
      final productId = await txn.insert('products', {
        ...data,
        'created_at': DateTime.now().toIso8601String(),
      });
      final qty = (data['quantity'] as num).toDouble();
      if (qty > 0) {
        await txn.insert('movements', {
          'product_id': productId,
          'product_name': data['name'],
          'type': 'in',
          'quantity': qty,
          'note': 'موجودی اولیه',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }


  Future<Map<String, dynamic>> createBackupData() async {
    final db = await database;
    final productRows = await db.query('products', orderBy: 'id ASC');
    final movementRows = await db.query('movements', orderBy: 'id ASC');

    return {
      'format': 'anbarban_backup',
      'schema_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'products': productRows,
      'movements': movementRows,
    };
  }

  Future<void> restoreBackupData(Map<String, dynamic> data) async {
    if (data['format'] != 'anbarban_backup' ||
        data['schema_version'] != 1) {
      throw Exception('قالب یا نسخه فایل پشتیبان پشتیبانی نمی‌شود.');
    }

    final rawProducts = data['products'];
    final rawMovements = data['movements'];

    if (rawProducts is! List || rawMovements is! List) {
      throw Exception('ساختار فایل پشتیبان معتبر نیست.');
    }

    if (rawProducts.length > 100000 || rawMovements.length > 1000000) {
      throw Exception('تعداد رکوردهای فایل بیش از حد مجاز است.');
    }

    final productsToRestore = <Map<String, Object?>>[];
    final movementsToRestore = <Map<String, Object?>>[];
    final productIds = <int>{};
    final movementIds = <int>{};

    bool validDate(Object? value) =>
        value is String &&
        value.isNotEmpty &&
        DateTime.tryParse(value) != null;

    bool validNumber(Object? value, {bool allowZero = true}) =>
        value is num &&
        value.isFinite &&
        (allowZero ? value >= 0 : value > 0);

    for (final item in rawProducts) {
      if (item is! Map) {
        throw Exception('رکورد کالا در فایل معتبر نیست.');
      }
      final row = Map<String, dynamic>.from(item);
      final id = row['id'];

      if (id is! int || id <= 0 || !productIds.add(id)) {
        throw Exception('شناسه کالای تکراری یا نامعتبر است.');
      }
      if (row['name'] is! String ||
          (row['name'] as String).trim().isEmpty ||
          row['sku'] is! String ||
          row['category'] is! String ||
          !validNumber(row['buy_price']) ||
          !validNumber(row['sell_price']) ||
          !validNumber(row['quantity']) ||
          !validNumber(row['min_quantity']) ||
          !validDate(row['created_at'])) {
        throw Exception('اطلاعات یکی از کالاها معتبر نیست.');
      }

      productsToRestore.add({
        'id': id,
        'name': row['name'],
        'sku': row['sku'],
        'category': row['category'],
        'buy_price': row['buy_price'],
        'sell_price': row['sell_price'],
        'quantity': row['quantity'],
        'min_quantity': row['min_quantity'],
        'created_at': row['created_at'],
      });
    }

    for (final item in rawMovements) {
      if (item is! Map) {
        throw Exception('رکورد گردش کالا در فایل معتبر نیست.');
      }
      final row = Map<String, dynamic>.from(item);
      final id = row['id'];
      final productId = row['product_id'];

      if (id is! int || id <= 0 || !movementIds.add(id)) {
        throw Exception('شناسه گردش تکراری یا نامعتبر است.');
      }
      if (productId != null &&
          (productId is! int || productId <= 0)) {
        throw Exception('شناسه کالای مرتبط با گردش معتبر نیست.');
      }
      if (row['product_name'] is! String ||
          (row['type'] != 'in' && row['type'] != 'out') ||
          !validNumber(row['quantity'], allowZero: false) ||
          row['note'] is! String ||
          !validDate(row['created_at'])) {
        throw Exception('اطلاعات یکی از گردش‌های کالا معتبر نیست.');
      }

      movementsToRestore.add({
        'id': id,
        'product_id': productId,
        'product_name': row['product_name'],
        'type': row['type'],
        'quantity': row['quantity'],
        'note': row['note'],
        'created_at': row['created_at'],
      });
    }

    final db = await database;

    // همه تغییرات در یک تراکنش‌اند؛ در صورت خطا، تراکنش لغو می‌شود.
    await db.transaction((txn) async {
      await txn.delete('movements');
      await txn.delete('products');

      for (final row in productsToRestore) {
        await txn.insert('products', row);
      }
      for (final row in movementsToRestore) {
        await txn.insert('movements', row);
      }
    });
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> moveStock({
    required int productId,
    required String type,
    required double quantity,
    required String note,
  }) async {
    if (type != 'in' && type != 'out') {
      throw Exception('نوع گردش کالا معتبر نیست.');
    }
    if (!quantity.isFinite || quantity <= 0) {
      throw Exception('مقدار باید عددی معتبر و بیشتر از صفر باشد.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('کالا پیدا نشد.');
      final product = rows.first;
      final current = (product['quantity'] as num).toDouble();
      if (type == 'out' && quantity > current) {
        throw Exception('موجودی کافی نیست. موجودی فعلی: ${number(current)}');
      }
      final next = type == 'in' ? current + quantity : current - quantity;
      await txn.update('products', {'quantity': next},
          where: 'id = ?', whereArgs: [productId]);
      await txn.insert('movements', {
        'product_id': productId,
        'product_name': product['name'],
        'type': type,
        'quantity': quantity,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnbarBanApp());
}

class AnbarBanApp extends StatelessWidget {
  const AnbarBanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'انباربان',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        scaffoldBackgroundColor: bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF17251F),
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE4EAE6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: green, width: 1.5),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  String search = '';
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> movements = [];
  Map<String, double> movementTotals = {'in': 0, 'out': 0};
  Map<String, double> todayMovementTotals = {'in': 0, 'out': 0};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final ps = await InventoryDb.instance.products();
      final ms = await InventoryDb.instance.movements();
      final totals = await InventoryDb.instance.movementTotals();
      final todayTotals = await InventoryDb.instance
          .movementTotalsForDay(DateTime.now());
      if (!mounted) return;
      setState(() {
        products = ps;
        movements = ms;
        movementTotals = totals;
        todayMovementTotals = todayTotals;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      message('خطا در خواندن اطلاعات: $e');
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> addProduct() async {
    final data = await showProductDialog(context);
    if (data == null) return;
    try {
      await InventoryDb.instance.saveProduct(data);
      await refresh();
      if (mounted) setState(() => tab = 1);
      message('کالا با موفقیت ثبت شد.');
    } catch (e) {
      message('ثبت کالا ناموفق بود: $e');
    }
  }

  Future<void> editProduct(Map<String, dynamic> product) async {
    final data = await showProductDialog(context, product: product);
    if (data == null) return;
    try {
      await InventoryDb.instance.saveProduct(
        data,
        id: (product['id'] as num).toInt(),
      );
      await refresh();
      message('اطلاعات کالا ویرایش شد.');
    } catch (e) {
      message('ویرایش ناموفق بود: $e');
    }
  }

  Future<void> deleteProduct(Map<String, dynamic> product) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کالا'),
        content: Text('کالای «${product['name']}» حذف شود؟ سوابق گردش حفظ می‌شوند.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await InventoryDb.instance.deleteProduct((product['id'] as num).toInt());
    await refresh();
    message('کالا حذف شد.');
  }

  Future<void> moveStock(String type) async {
    if (products.isEmpty) {
      message('ابتدا یک کالا ثبت کن.');
      return;
    }
    final result = await showMovementDialog(context, products, type);
    if (result == null) return;
    try {
      await InventoryDb.instance.moveStock(
        productId: result['product_id'] as int,
        type: type,
        quantity: result['quantity'] as double,
        note: result['note'] as String,
      );
      await refresh();
      message(type == 'in' ? 'ورود کالا ثبت شد.' : 'خروج کالا ثبت شد.');
    } catch (e) {
      message(e.toString().replaceFirst('Exception: ', ''));
    }
  }


  Future<void> exportBackup() async {
    try {
      final data = await InventoryDb.instance.createBackupData();
      final jsonText = const JsonEncoder.withIndent('  ').convert(data);
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-');
      final file = File(p.join(directory.path, 'anbarban-backup-$stamp.json'));

      await file.writeAsString(jsonText, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'نسخه پشتیبان اطلاعات انباربان',
      );
    } catch (e) {
      message('ساخت یا اشتراک‌گذاری پشتیبان ناموفق بود: $e');
    }
  }

  Future<void> importBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.single;
      final bytes = file.bytes;

      if (file.size > 20 * 1024 * 1024) {
        message('حجم فایل پشتیبان نباید بیشتر از ۲۰ مگابایت باشد.');
        return;
      }
      if (bytes == null) {
        message('خواندن فایل انتخاب‌شده امکان‌پذیر نیست.');
        return;
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        message('ساختار فایل پشتیبان معتبر نیست.');
        return;
      }

      final backup = Map<String, dynamic>.from(decoded);
      final products = backup['products'];
      final movements = backup['movements'];

      if (backup['format'] != 'anbarban_backup' ||
          backup['schema_version'] != 1 ||
          products is! List ||
          movements is! List) {
        message('این فایل، پشتیبان معتبر انباربان نیست.');
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('جایگزینی اطلاعات انبار؟'),
            content: Text(
              'این فایل شامل ${fa('${products.length}')} کالا و '
              '${fa('${movements.length}')} گردش است.\n\n'
              'با ادامه، اطلاعات فعلی جایگزین می‌شود. '
              'قبل از ادامه، از اطلاعات فعلی نسخه پشتیبان بگیر.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('جایگزینی اطلاعات'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;

      await InventoryDb.instance.restoreBackupData(backup);
      await refresh();

      message(
        'بازیابی موفق بود: ${fa('${products.length}')} کالا و '
        '${fa('${movements.length}')} گردش.',
      );
    } catch (e) {
      message('بازیابی انجام نشد؛ اطلاعات فعلی باید حفظ شده باشند. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['داشبورد', 'کالاها', 'گردش کالا', 'گزارش‌ها'];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Text(titles[tab]),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'به‌روزرسانی',
              onPressed: refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'پشتیبان‌گیری و بازیابی',
              onSelected: (value) {
                if (value == 'backup') {
                  exportBackup();
                } else if (value == 'restore') {
                  importBackup();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'backup',
                  child: Row(
                    children: [
                      Icon(Icons.backup_outlined),
                      SizedBox(width: 10),
                      Text('تهیه نسخه پشتیبان'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore_rounded),
                      SizedBox(width: 10),
                      Text('بازیابی نسخه پشتیبان'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: tab,
                children: [
                  dashboard(),
                  productPage(),
                  movementPage(),
                  reportPage(),
                ],
              ),
        floatingActionButton: tab == 1
            ? FloatingActionButton.extended(
                onPressed: addProduct,
                backgroundColor: green,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('ثبت کالا'),
              )
            : tab == 2
                ? FloatingActionButton(
                    onPressed: () => showMovementChoices(),
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.swap_vert_rounded),
                  )
                : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'خانه',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'کالاها',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_rounded),
              label: 'گردش',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'گزارش',
            ),
          ],
        ),
      ),
    );
  }

  Widget dashboard() {
    final low = products.where((x) =>
        (x['quantity'] as num) <= (x['min_quantity'] as num)).length;
    final totalQty = products.fold<double>(
        0, (sum, x) => sum + (x['quantity'] as num).toDouble());
    final totalValue = products.fold<double>(
        0,
        (sum, x) =>
            sum +
            (x['quantity'] as num).toDouble() *
                (x['buy_price'] as num).toDouble());
    final todayIn = todayMovementTotals['in'] ?? 0;
    final todayOut = todayMovementTotals['out'] ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF176B55), Color(0xFF25866B)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('مدیریت انبار، ساده و دقیق',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              SizedBox(height: 8),
              Text('خوش آمدید 👋',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('اطلاعات شما روی همین دستگاه ذخیره می‌شود.',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            SummaryCard(title: 'تعداد کالاها', value: number(products.length),
                icon: Icons.inventory_2_outlined, color: green),
            SummaryCard(title: 'موجودی کل', value: number(totalQty),
                icon: Icons.warehouse_outlined, color: Colors.blue),
            SummaryCard(title: 'ورود امروز', value: number(todayIn),
                icon: Icons.move_to_inbox_outlined, color: Colors.teal),
            SummaryCard(title: 'خروج امروز', value: number(todayOut),
                icon: Icons.outbox_outlined, color: Colors.deepOrange),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF0D8),
              child: Icon(Icons.warning_amber_rounded, color: Colors.orange),
            ),
            title: const Text('هشدار موجودی کم'),
            subtitle: Text(low == 0
                ? 'کالای کم‌موجودی ندارید.'
                : '${number(low)} کالا به حداقل موجودی رسیده است.'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => setState(() {
              search = '';
              tab = 1;
            }),
          ),
        ),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE5F1EC),
              child: Icon(Icons.payments_outlined, color: green),
            ),
            title: const Text('ارزش خرید موجودی'),
            subtitle: Text(money(totalValue)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('عملیات سریع',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: addProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('کالای جدید'),
                style: FilledButton.styleFrom(
                    backgroundColor: green, padding: const EdgeInsets.all(14)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => moveStock('in'),
                icon: const Icon(Icons.south_west_rounded),
                label: const Text('ورود کالا'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(14)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => moveStock('out'),
          icon: const Icon(Icons.north_east_rounded),
          label: const Text('ثبت خروج کالا'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(14), minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 18),
        const Text('آخرین گردش‌ها',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (movements.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'هنوز گردش کالایی ثبت نشده',
            subtitle: 'پس از ثبت ورود یا خروج، سوابق اینجا نمایش داده می‌شوند.',
          )
        else
          ...movements.take(5).map(movementTile),
      ],
    );
  }

  Widget productPage() {
    final filtered = products.where((x) {
      final q = search.trim().toLowerCase();
      return q.isEmpty ||
          (x['name'] as String).toLowerCase().contains(q) ||
          (x['sku'] as String).toLowerCase().contains(q) ||
          (x['category'] as String).toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: 'جست‌وجوی نام، کد یا دسته کالا',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'کالایی پیدا نشد',
                  subtitle: 'با دکمه «ثبت کالا» اولین کالا را اضافه کن.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final x = filtered[i];
                    final qty = (x['quantity'] as num).toDouble();
                    final min = (x['min_quantity'] as num).toDouble();
                    final isLow = qty <= min;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 9),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isLow
                                ? const Color(0xFFFFE9D7)
                                : const Color(0xFFE5F1EC),
                            child: Icon(
                              isLow
                                  ? Icons.warning_amber_rounded
                                  : Icons.inventory_2_outlined,
                              color: isLow ? Colors.deepOrange : green,
                            ),
                          ),
                          title: Text(x['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${(x['sku'] as String).isEmpty ? 'بدون کد' : 'کد: ${x['sku']}'}\nموجودی: ${number(qty)}  •  قیمت فروش: ${money(x['sell_price'])}',
                            ),
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') editProduct(x);
                              if (v == 'delete') deleteProduct(x);
                              if (v == 'in') moveStock('in');
                              if (v == 'out') moveStock('out');
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('ویرایش کالا')),
                              PopupMenuItem(value: 'in', child: Text('ثبت ورود')),
                              PopupMenuItem(value: 'out', child: Text('ثبت خروج')),
                              PopupMenuItem(value: 'delete', child: Text('حذف کالا')),
                            ],
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

  Widget movementPage() {
    if (movements.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_horiz_rounded,
        title: 'گردشی ثبت نشده',
        subtitle: 'با دکمه پایین، ورود یا خروج کالا را ثبت کن.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: movements.length,
      itemBuilder: (_, i) => movementTile(movements[i]),
    );
  }

  Widget movementTile(Map<String, dynamic> m) {
    final isIn = m['type'] == 'in';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isIn ? const Color(0xFFE3F4EA) : const Color(0xFFFFE9E4),
          child: Icon(
            isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: isIn ? green : Colors.deepOrange,
          ),
        ),
        title: Text(m['product_name'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${isIn ? 'ورود' : 'خروج'} • ${dateText(m['created_at'] as String?)}'
          '${(m['note'] as String).isEmpty ? '' : '\n${m['note']}'}',
        ),
        isThreeLine: (m['note'] as String).isNotEmpty,
        trailing: Text(
          '${isIn ? '+' : '−'}${number(m['quantity'])}',
          style: TextStyle(
            color: isIn ? green : Colors.deepOrange,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget reportPage() {
    final low = products.where((x) =>
        (x['quantity'] as num) <= (x['min_quantity'] as num)).toList();
    final value = products.fold<double>(
        0,
        (s, x) =>
            s +
            (x['quantity'] as num).toDouble() *
                (x['buy_price'] as num).toDouble());
    final inCount = movementTotals['in'] ?? 0;
    final outCount = movementTotals['out'] ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('گزارش خلاصه',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        reportCard('تعداد اقلام تعریف‌شده', number(products.length),
            Icons.inventory_2_outlined),
        reportCard('ارزش خرید موجودی فعلی', money(value),
            Icons.account_balance_wallet_outlined),
        reportCard('مجموع مقدار ورود ثبت‌شده', number(inCount),
            Icons.south_west_rounded),
        reportCard('مجموع مقدار خروج ثبت‌شده', number(outCount),
            Icons.north_east_rounded),
        const SizedBox(height: 12),
        const Text('کالاهای نیازمند تأمین',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (low.isEmpty)
          const EmptyState(
            icon: Icons.check_circle_outline,
            title: 'موجودی همه کالاها کافی است',
            subtitle: 'با تعیین حداقل موجودی، هشدارها دقیق‌تر می‌شوند.',
          )
        else
          ...low.map((x) => Card(
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded,
                      color: Colors.deepOrange),
                  title: Text(x['name'] as String),
                  subtitle: Text(
                      'موجودی ${number(x['quantity'])} • حداقل ${number(x['min_quantity'])}'),
                ),
              )),
        const SizedBox(height: 12),
        const Text(
          'مبالغ بر اساس قیمت خرید ثبت‌شده محاسبه می‌شوند. این گزارش فعلاً فایل خروجی اکسل یا PDF تولید نمی‌کند.',
          style: TextStyle(color: Colors.black54, height: 1.7),
        ),
      ],
    );
  }

  Widget reportCard(String title, String value, IconData icon) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE5F1EC),
          child: Icon(icon, color: green),
        ),
        title: Text(title),
        trailing: Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> showMovementChoices() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.south_west_rounded, color: green),
              title: const Text('ثبت ورود کالا'),
              onTap: () => Navigator.pop(ctx, 'in'),
            ),
            ListTile(
              leading: const Icon(Icons.north_east_rounded,
                  color: Colors.deepOrange),
              title: const Text('ثبت خروج کالا'),
              onTap: () => Navigator.pop(ctx, 'out'),
            ),
          ],
        ),
      ),
    );
    if (choice != null) await moveStock(choice);
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 25),
          Text(value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.7)),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showProductDialog(
  BuildContext context, {
  Map<String, dynamic>? product,
}) async {
  final editing = product != null;
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: product?['name'] as String? ?? '');
  final sku = TextEditingController(text: product?['sku'] as String? ?? '');
  final category = TextEditingController(text: product?['category'] as String? ?? '');
  final buy = TextEditingController(text: '${product?['buy_price'] ?? ''}');
  final sell = TextEditingController(text: '${product?['sell_price'] ?? ''}');
  final qty = TextEditingController();
  final min = TextEditingController(text: '${product?['min_quantity'] ?? 0}');

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(editing ? 'ویرایش کالا' : 'ثبت کالای جدید'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'نام کالا *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'نام کالا الزامی است' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: sku,
                    decoration: const InputDecoration(labelText: 'کد کالا / بارکد'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: category,
                    decoration: const InputDecoration(labelText: 'دسته‌بندی'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: buy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'قیمت خرید (تومان)'),
                    validator: (v) {
                      final n = tryParseNumber(v ?? '');
                      if (n == null) return 'قیمت خرید را به‌صورت عدد وارد کن';
                      if (n < 0) return 'قیمت منفی مجاز نیست';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: sell,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'قیمت فروش (تومان)'),
                    validator: (v) {
                      final n = tryParseNumber(v ?? '');
                      if (n == null) return 'قیمت فروش را به‌صورت عدد وارد کن';
                      if (n < 0) return 'قیمت منفی مجاز نیست';
                      return null;
                    },
                  ),
                  if (!editing) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: qty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'موجودی اولیه'),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return null;
                        final n = tryParseNumber(v ?? '');
                        if (n == null) return 'موجودی را به‌صورت عدد وارد کن';
                        if (n < 0) return 'موجودی منفی مجاز نیست';
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: min,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'حداقل موجودی برای هشدار'),
                    validator: (v) {
                      final n = tryParseNumber(v ?? '');
                      if (n == null) return 'حداقل موجودی را به‌صورت عدد وارد کن';
                      if (n < 0) return 'حداقل موجودی منفی مجاز نیست';
                      return null;
                    },
                  ),
                  if (editing)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'برای تغییر تعداد موجودی، از عملیات ورود یا خروج استفاده کن تا سابقه ثبت شود.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final b = tryParseNumber(buy.text)!;
              final s = tryParseNumber(sell.text)!;
              final q = qty.text.trim().isEmpty
                  ? 0.0
                  : tryParseNumber(qty.text)!;
              final m = tryParseNumber(min.text)!;
              if (b < 0 || s < 0 || q < 0 || m < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('مقادیر منفی مجاز نیستند.')),
                );
                return;
              }
              Navigator.pop(ctx, <String, dynamic>{
                'name': name.text.trim(),
                'sku': sku.text.trim(),
                'category': category.text.trim(),
                'buy_price': b,
                'sell_price': s,
                'quantity': q,
                'min_quantity': m,
              });
            },
            child: Text(editing ? 'ذخیره تغییرات' : 'ثبت کالا'),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> showMovementDialog(
  BuildContext context,
  List<Map<String, dynamic>> products,
  String type,
) async {
  final formKey = GlobalKey<FormState>();
  final qty = TextEditingController();
  final note = TextEditingController();
  int? selected = (products.first['id'] as num).toInt();

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(type == 'in' ? 'ثبت ورود کالا' : 'ثبت خروج کالا'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'انتخاب کالا'),
                    items: products.map((x) {
                      final id = (x['id'] as num).toInt();
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          '${x['name']} (موجودی: ${number(x['quantity'])})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setLocal(() => selected = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'تعداد *'),
                    validator: (v) {
                      final value = v == null ? null : tryParseNumber(v);
                      if (value == null || value <= 0) {
                        return 'عدد معتبر و بیشتر از صفر وارد کن';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate() || selected == null) return;
                Navigator.pop(ctx, <String, dynamic>{
                  'product_id': selected!,
                  'quantity': tryParseNumber(qty.text)!,
                  'note': note.text.trim(),
                });
              },
              child: const Text('ثبت عملیات'),
            ),
          ],
        ),
      ),
    ),
  );
}
