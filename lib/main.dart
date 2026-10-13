import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
      supportedLocales: const [
        Locale('fa'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B55),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFFF6F8F7),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'انباربان',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              tooltip: 'تنظیمات',
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'خوش آمدید',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'مدیریت ساده و سریع موجودی انبار',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SummaryCard(
                    title: 'تعداد کالاها',
                    value: '۰',
                    icon: Icons.inventory_2_outlined,
                  ),
                  SummaryCard(
                    title: 'ورود امروز',
                    value: '۰',
                    icon: Icons.move_to_inbox_outlined,
                  ),
                  SummaryCard(
                    title: 'خروج امروز',
                    value: '۰',
                    icon: Icons.outbox_outlined,
                  ),
                  SummaryCard(
                    title: 'هشدار موجودی',
                    value: '۰',
                    icon: Icons.warning_amber_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'عملیات سریع',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.add_box_outlined,
                title: 'ثبت کالای جدید',
                subtitle: 'تعریف کالا و مشخصات آن',
                onTap: () => _showMessage(context, 'بخش کالاها در مرحله بعد ساخته می‌شود.'),
              ),
              _ActionTile(
                icon: Icons.login_outlined,
                title: 'ثبت ورود کالا',
                subtitle: 'افزایش موجودی انبار',
                onTap: () => _showMessage(context, 'فرم ورود در مرحله بعد ساخته می‌شود.'),
              ),
              _ActionTile(
                icon: Icons.logout_outlined,
                title: 'ثبت خروج کالا',
                subtitle: 'کاهش موجودی انبار',
                onTap: () => _showMessage(context, 'فرم خروج در مرحله بعد ساخته می‌شود.'),
              ),
              _ActionTile(
                icon: Icons.bar_chart_outlined,
                title: 'گزارش موجودی',
                subtitle: 'مشاهده گردش و وضعیت کالاها',
                onTap: () => _showMessage(context, 'گزارش‌ها در مرحله بعد ساخته می‌شوند.'),
              ),
              const SizedBox(height: 12),
              const Text(
                'نسخه آزمایشی ۰.۱.۰',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 26, color: const Color(0xFF176B55)),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE6F2ED),
          foregroundColor: const Color(0xFF176B55),
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
