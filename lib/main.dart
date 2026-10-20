import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String kApiKey = 'd197d588cf1741f8a9f3cf3c1acd5b64';

void main() => runApp(const BeritaApp());

class Pal {
  static const navy = Color(0xFF05579B);

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color panel(BuildContext c) =>
      _dark(c) ? const Color(0xFF0B3E73) : navy;
  static Color title(BuildContext c) =>
      _dark(c) ? const Color(0xFF8AB4F8) : const Color(0xFF1D56A5);
  static Color card(BuildContext c) =>
      _dark(c) ? const Color(0xFF1B2230) : const Color(0xFFF8F9FB);
  static Color chipBg(BuildContext c) =>
      _dark(c) ? const Color(0xFF2B3F66) : const Color(0xFF9DB7F0);
  static Color chipFg(BuildContext c) =>
      _dark(c) ? const Color(0xFFD6E3FF) : const Color(0xFF1B3A7A);
  static Color muted(BuildContext c) =>
      _dark(c) ? Colors.white60 : const Color(0xFF8A8F98);
  static Color circle(BuildContext c) =>
      _dark(c) ? const Color(0xFF3B5A94) : const Color(0xFF93B1E6);
  static Color bar(BuildContext c) =>
      _dark(c) ? const Color(0xFF12151C) : Colors.white;
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class BeritaApp extends StatelessWidget {
  const BeritaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Berita Hari Ini',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorSchemeSeed: Pal.navy,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Pal.navy,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const NewsPage(),
    );
  }
}

class Topic {
  final String label;
  final String query;
  final String? language;

  const Topic(this.label, this.query, {this.language});
}

const List<Topic> kTopics = [
  Topic('Apple', 'apple', language: 'en'),
  Topic('Teknologi', 'teknologi', language: 'id'),
  Topic('Bisnis', 'bisnis', language: 'id'),
  Topic('Olahraga', 'olahraga', language: 'id'),
  Topic('Indonesia', 'indonesia', language: 'id'),
];

class Article {
  final String title;
  final String description;
  final String content;
  final String imageUrl;
  final String sourceName;
  final String url;
  final DateTime publishedAt;

  Article({
    required this.title,
    required this.description,
    required this.content,
    required this.imageUrl,
    required this.sourceName,
    required this.url,
    required this.publishedAt,
  });

  factory Article.fromNewsApi(Map<String, dynamic> json) {
    final rawContent = (json['content'] ?? '') as String;
    return Article(
      title: json['title'] ?? '-',
      description: json['description'] ?? '',
      content: rawContent.replaceAll(RegExp(r'\s*\[\+\d+ chars\]$'), ''),
      imageUrl: json['urlToImage'] ?? '',
      sourceName: (json['source']?['name']) ?? '',
      url: json['url'] ?? '',
      publishedAt:
          DateTime.tryParse(json['publishedAt'] ?? '') ?? DateTime.now(),
    );
  }

  factory Article.fromSpaceflight(Map<String, dynamic> json) {
    return Article(
      title: json['title'] ?? '-',
      description: json['summary'] ?? '',
      content: '',
      imageUrl: json['image_url'] ?? '',
      sourceName: json['news_site'] ?? '',
      url: json['url'] ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] ?? '') ?? DateTime.now(),
    );
  }

  static const _bulan = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  String get shortDate {
    final l = publishedAt.toLocal();
    return '${l.day} ${_bulan[l.month - 1]} ${l.year}';
  }

  String get fullDate {
    final l = publishedAt.toLocal();
    final jam = l.hour.toString().padLeft(2, '0');
    final menit = l.minute.toString().padLeft(2, '0');
    return '$shortDate, $jam:$menit';
  }
}


class ApiException implements Exception {
  final String message;
  final bool keyProblem;
  ApiException(this.message, {this.keyProblem = false});
}

class FeedResult {
  final List<Article> articles;
  final bool fallback;
  final String? notice;

  FeedResult(this.articles, this.fallback, this.notice);
}

class NewsService {
  final Map<String, FeedResult> _cache = {};

  Future<FeedResult> fetch(Topic topic) async {
    String notice;

    try {
      final list = await _fetchNewsApi(topic);
      if (list.isNotEmpty) {
        final result = FeedResult(list, false, null);
        _cache[topic.query] = result;
        return result;
      }
      notice = 'NewsAPI belum menemukan berita untuk topik ini.';
    } on ApiException catch (e) {
      notice = e.keyProblem
          ? 'API key NewsAPI belum valid, jadi ditampilkan berita cadangan.'
          : e.message;
    } catch (_) {
      notice = 'NewsAPI tidak dapat dihubungi.';
    }

    try {
      final list = await _fetchSpaceflight(topic);
      final result = FeedResult(
        list,
        true,
        '$notice Menampilkan berita dari sumber cadangan.',
      );
      _cache[topic.query] = result;
      return result;
    } catch (_) {

      final cached = _cache[topic.query];
      if (cached != null) {
        return FeedResult(
          cached.articles,
          true,
          'Sedang offline. Menampilkan berita yang tersimpan.',
        );
      }
      throw ApiException(
        'Tidak dapat memuat berita.\nPeriksa koneksi internet kamu.',
      );
    }
  }

  Future<List<Article>> _fetchNewsApi(Topic topic) async {
    if (kApiKey.trim().isEmpty ||
        kApiKey.contains('ISI_API_KEY') ||
        kApiKey.startsWith('http')) {
      throw ApiException('API key belum diisi.', keyProblem: true);
    }

    final from = DateTime.now().subtract(const Duration(days: 7));
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';

    final uri = Uri.https('newsapi.org', '/v2/everything', {
      'q': topic.query,
      if (topic.language != null) 'language': topic.language!,
      'from': fromStr,
      'sortBy': 'popularity',
      'pageSize': '30',
      'apiKey': kApiKey.trim(),
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 12));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Respons NewsAPI tidak valid.');
    }

    if (response.statusCode != 200 || data['status'] != 'ok') {
      final code = data['code'] as String?;
      final keyProblem = code == 'apiKeyInvalid' ||
          code == 'apiKeyMissing' ||
          code == 'apiKeyDisabled';
      final limited = code == 'rateLimited';
      throw ApiException(
        limited
            ? 'Jatah harian NewsAPI habis.'
            : (data['message']?.toString() ?? 'Gagal memuat NewsAPI.'),
        keyProblem: keyProblem,
      );
    }

    return _dedupe((data['articles'] as List<dynamic>)
        .map((e) => Article.fromNewsApi(e as Map<String, dynamic>))
        .where((a) => a.title != '[Removed]' && a.url.isNotEmpty)
        .toList());
  }

  Future<List<Article>> _fetchSpaceflight(Topic topic) async {
    Future<List<Article>> call(String? search) async {
      final uri = Uri.https('api.spaceflightnewsapi.net', '/v4/articles/', {
        'limit': '30',
        if (search != null) 'search': search,
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw ApiException('Sumber cadangan gagal (${response.statusCode}).');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['results'] as List<dynamic>)
          .map((e) => Article.fromSpaceflight(e as Map<String, dynamic>))
          .where((a) => a.url.isNotEmpty)
          .toList();
    }

    var list = await call(topic.query);
    if (list.isEmpty) list = await call(null);
    return _dedupe(list);
  }

  List<Article> _dedupe(List<Article> list) {
    final seen = <String>{};
    return list.where((a) => seen.add(a.url)).toList();
  }
}

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak dapat membuka tautan')),
    );
  }
}


class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final _service = NewsService();
  final _scrollController = ScrollController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  FeedResult? _feed;
  bool _loading = true;
  String? _error;
  bool _showBackToTop = false;
  int _topicIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showBackToTop) {
      setState(() => _showBackToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _load() async {
    try {
      final result = await _service.fetch(kTopics[_topicIndex]);
      if (!mounted) return;
      setState(() {
        _feed = result;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Terjadi kesalahan saat memuat berita.';
        _loading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _load();
    if (!mounted) return;
    final ok = _error == null;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(ok
                  ? 'Berita berhasil diperbarui'
                  : 'Gagal memperbarui berita'),
            ),
          ],
        ),
      ),
    );
  }

  void _selectTopic(int index) {
    if (index == _topicIndex) return;
    setState(() {
      _topicIndex = index;
      _feed = null;
      _loading = true;
      _error = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load();
  }

  void _openDetail(Article article) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 900;

    final sidePad = math.max(16.0, (width - 1200) / 2 + 16);

    return Scaffold(
      body: RefreshIndicator(
        key: _refreshKey,
        onRefresh: _onRefresh,
        edgeOffset: 116,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildNavBar(),
            ..._buildContentSlivers(wide, sidePad),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _showBackToTop
                ? Padding(
                    key: const ValueKey('up'),
                    padding: const EdgeInsets.only(right: 12),
                    child: CircleIconButton(
                      icon: Icons.keyboard_arrow_up_rounded,
                      tooltip: 'Kembali ke atas',
                      onTap: _scrollToTop,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
          CircleIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Muat ulang',
            onTap: () => _refreshKey.currentState?.show(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      centerTitle: true,
      toolbarHeight: 68,
      elevation: 0,
      scrolledUnderElevation: 3,
      shadowColor: Colors.black38,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Pal.bar(context),
      title: const BrandLogo(),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: TopicTabs(
              selected: _topicIndex,
              onSelect: _selectTopic,
              height: 48,
              center: true,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContentSlivers(bool wide, double sidePad) {
    if (_loading) {
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePad, 16, sidePad, 0),
          sliver: SliverList.separated(
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (_, __) => const SkeletonCard(),
          ),
        ),
      ];
    }

    final articles = _feed?.articles ?? [];

    if (articles.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _error != null
              ? ErrorView(
                  message: _error!,
                  onRetry: () {
                    setState(() => _loading = true);
                    _load();
                  },
                )
              : const EmptyView(),
        ),
      ];
    }

    final hero = articles.first;
    final rest = articles.skip(1).toList();
    final panelItems = rest.take(5).toList();

    return [
      if (_feed?.notice != null)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePad, 12, sidePad, 0),
          sliver: SliverToBoxAdapter(child: NoticeBanner(text: _feed!.notice!)),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(sidePad, 14, sidePad, 0),
        sliver: SliverToBoxAdapter(
          child: HeroBanner(
            article: hero,
            height: wide ? 340 : 230,
            onTap: () => _openDetail(hero),
          ),
        ),
      ),
      if (rest.isNotEmpty && wide)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePad, 36, sidePad, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: LatestPanel(items: panelItems, onTap: _openDetail),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    children: [
                      for (final a in rest)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: NewsListCard(
                            article: a,
                            wide: true,
                            onTap: () => _openDetail(a),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (rest.isNotEmpty && !wide) ...[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePad, 28, sidePad, 0),
          sliver: SliverToBoxAdapter(
            child: LatestPanel(items: panelItems, onTap: _openDetail),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePad, 24, sidePad, 0),
          sliver: SliverList.separated(
            itemCount: rest.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) => NewsListCard(
              article: rest[i],
              wide: false,
              onTap: () => _openDetail(rest[i]),
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 110),
          child: Center(
            child: Text(
              'Kamu sudah sampai di akhir berita',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Pal.muted(context)),
            ),
          ),
        ),
      ),
    ];
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Pal.navy,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.newspaper, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BERITA HARI INI',
              style: TextStyle(
                color: Pal.title(context),
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              'KABAR TERKINI UNTUKMU',
              style: TextStyle(
                color: Pal.title(context),
                fontWeight: FontWeight.w600,
                fontSize: 8.5,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TopicTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;
  final bool center;

  const TopicTabs({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.height,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        // shrinkWrap membuat tab menyusut sesuai isi sehingga bisa
        // ditengahkan; tetap bisa di-scroll kalau kepanjangan
        shrinkWrap: center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: kTopics.length,
        itemBuilder: (context, i) {
          final isSel = i == selected;
          return InkWell(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSel ? Pal.title(context) : Colors.transparent,
                    width: 3.5,
                  ),
                ),
              ),
              child: Text(
                kTopics[i].label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? onSurface : Pal.title(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Pal.circle(context),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}


class LatestPanel extends StatelessWidget {
  final List<Article> items;
  final ValueChanged<Article> onTap;

  const LatestPanel({super.key, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Berita Terbaru',
          style: TextStyle(
            color: Pal.title(context),
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: Pal.panel(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                InkWell(
                  onTap: () => onTap(items[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        items[i].title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
                if (i != items.length - 1)
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class NewsListCard extends StatelessWidget {
  final Article article;
  final bool wide;
  final VoidCallback onTap;

  const NewsListCard({
    super.key,
    required this.article,
    required this.wide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imgW = wide ? 260.0 : 112.0;
    final imgH = wide ? 172.0 : 112.0;

    return Container(
      decoration: BoxDecoration(
        color: Pal.card(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(wide ? 16 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: imgW,
                    height: imgH,
                    child: Hero(
                      tag: 'img_${article.url}',
                      child: NewsImage(url: article.imageUrl, height: imgH),
                    ),
                  ),
                ),
                SizedBox(width: wide ? 20 : 12),
                Expanded(
                  child: SizedBox(
                    height: imgH,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: wide ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Pal.title(context),
                            fontSize: wide ? 19 : 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (wide && article.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            article.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              article.shortDate,
                              style: TextStyle(
                                color: Pal.muted(context),
                                fontSize: wide ? 14 : 11.5,
                              ),
                            ),
                            if (article.sourceName.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: wide ? 12 : 8,
                                    vertical: wide ? 5 : 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Pal.chipBg(context),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    article.sourceName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Pal.chipFg(context),
                                      fontSize: wide ? 13.5 : 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
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

// ======================= BANNER BERITA UTAMA =======================

class HeroBanner extends StatelessWidget {
  final Article article;
  final double height;
  final VoidCallback onTap;

  const HeroBanner({
    super.key,
    required this.article,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'img_${article.url}',
                  child: NewsImage(url: article.imageUrl, height: height),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                      stops: [0.3, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (article.sourceName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Pal.chipBg(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            article.sourceName,
                            style: TextStyle(
                              color: Pal.chipFg(context),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        article.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        article.shortDate,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
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

class DetailPage extends StatelessWidget {
  final Article article;

  const DetailPage({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final paragraphs = <String>[];
    if (article.description.isNotEmpty) paragraphs.add(article.description);
    if (article.content.isNotEmpty &&
        !article.description.contains(article.content) &&
        !article.content.contains(article.description)) {
      paragraphs.add(article.content);
    } else if (article.content.length > article.description.length) {
      paragraphs
        ..clear()
        ..add(article.content);
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: Pal.navy,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  NewsImage(url: article.imageUrl, height: 300),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                        stops: [0, 0.4],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (article.sourceName.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: Pal.chipBg(context),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                article.sourceName,
                                style: TextStyle(
                                  color: Pal.chipFg(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          Text(
                            article.fullDate,
                            style: TextStyle(color: Pal.muted(context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        article.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Pal.title(context),
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final p in paragraphs) ...[
                        SelectableText(
                          p,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(height: 1.65),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => openUrl(context, article.url),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Baca artikel lengkap'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Pal.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NewsImage extends StatelessWidget {
  final String url;
  final double? height;

  const NewsImage({super.key, required this.url, this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget placeholder(Widget child) => Container(
          height: height,
          width: double.infinity,
          color: scheme.surfaceContainerHighest,
          child: Center(child: child),
        );

    if (url.isEmpty) {
      return placeholder(
          Icon(Icons.image_not_supported_outlined, color: scheme.outline));
    }

    return Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder(const CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (_, __, ___) => placeholder(
          Icon(Icons.broken_image_outlined, color: scheme.outline)),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  final String text;

  const NoticeBanner({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Pal.card(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(double.infinity, 16),
                const SizedBox(height: 8),
                bar(double.infinity, 16),
                const SizedBox(height: 8),
                bar(120, 16),
                const SizedBox(height: 14),
                bar(90, 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 72, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Oops, berita gagal dimuat',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
            style: FilledButton.styleFrom(backgroundColor: Pal.navy),
          ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded,
              size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Belum ada berita untuk topik ini',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tarik layar ke bawah untuk memuat ulang\natau pilih topik lain.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}