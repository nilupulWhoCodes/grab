import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/youtube_service.dart';
import '../theme.dart';
import 'download_sheet.dart';

const _home = 'https://m.youtube.com';

/// In-app browser on YouTube's mobile site with a "Download MP3" bar that
/// appears whenever a video is open.
class BrowseView extends StatefulWidget {
  const BrowseView({super.key, required this.onDownloadStarted});

  final VoidCallback onDownloadStarted;

  @override
  State<BrowseView> createState() => BrowseViewState();
}

class BrowseViewState extends State<BrowseView> {
  late final WebViewController _controller;
  String _url = _home;
  String? _videoId;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final u = req.url;
          // Keep everything inside the app instead of jumping to other apps.
          if (u.startsWith('intent:') ||
              u.startsWith('vnd.youtube') ||
              u.startsWith('market:')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (change) => _setUrl(change.url),
        onPageStarted: _setUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ))
      ..loadRequest(Uri.parse(_home));
  }

  void _setUrl(String? url) {
    if (url == null || !mounted) return;
    final id = YoutubeService.videoIdFrom(url);
    setState(() {
      _url = url;
      _videoId = id;
    });
    if (id != null) {
      // Warm the cache so the bar and sheet show the title quickly.
      YoutubeService.instance.info(id).then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }
  }

  Future<bool> goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return true;
    }
    return false;
  }

  String get _displayUrl {
    final uri = Uri.tryParse(_url);
    if (uri == null) return _url;
    final q = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.host}${uri.path}$q';
  }

  Future<void> _openDownload(String id) async {
    final started = await showDownloadSheet(context, id);
    if (started == true) widget.onDownloadStarted();
  }

  Future<void> _pasteLink() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final controller = TextEditingController(
      text: YoutubeService.videoIdFrom(clip?.text) != null ? clip!.text : '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open a link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'YouTube link or search',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    final text = value?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    final id = YoutubeService.videoIdFrom(text);
    if (id != null) {
      _controller.loadRequest(Uri.parse('https://m.youtube.com/watch?v=$id'));
      _openDownload(id);
    } else {
      _controller.loadRequest(Uri.parse(
          'https://m.youtube.com/results?search_query=${Uri.encodeQueryComponent(text)}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: goBack,
                icon: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.text, size: 28),
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Open a link',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pasteLink,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 14, color: AppColors.sub),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _displayUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.sub),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: () => _controller.reload(),
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.text, size: 22),
              ),
            ],
          ),
        ),
        if (_progress < 100)
          LinearProgressIndicator(
            value: _progress / 100,
            minHeight: 2,
            backgroundColor: AppColors.line,
          )
        else
          const Divider(height: 2, thickness: 1, color: AppColors.line),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              if (_videoId != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _DetectedBar(
                    videoId: _videoId!,
                    onDownload: () => _openDownload(_videoId!),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetectedBar extends StatelessWidget {
  const _DetectedBar({required this.videoId, required this.onDownload});

  final String videoId;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x73000000), blurRadius: 32, offset: Offset(0, 12)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.placeholder,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note_rounded,
                color: AppColors.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<VideoInfo>(
              future: YoutubeService.instance.info(videoId),
              builder: (context, snap) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'VIDEO DETECTED',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snap.data?.title ?? 'Loading title…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onDownload,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bg,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text('MP3'),
          ),
        ],
      ),
    );
  }
}
