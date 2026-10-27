import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../theme.dart';

/// Shows the download options sheet. Resolves to true when a download started.
Future<bool?> showDownloadSheet(BuildContext context, String videoId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    barrierColor: const Color(0x8C000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _DownloadSheet(videoId: videoId),
  );
}

String formatDuration(Duration? d) {
  if (d == null) return '';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.videoId});

  final String videoId;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  static const _qualities = [
    (128, 'Smaller'),
    (192, 'Standard'),
    (320, 'Best'),
  ];

  late final Future<VideoInfo> _info;
  final _title = TextEditingController();
  final _artist = TextEditingController();
  int _bitrate = 192;
  String _saveLabel = 'Music / Grab';
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _info = YoutubeService.instance.info(widget.videoId);
    _info.then((v) {
      if (mounted && !_touched) {
        final guess = TagGuess.from(v.title, v.author);
        _title.text = guess.title;
        _artist.text = guess.artist;
        setState(() {});
      }
    }).catchError((_) {});
    StorageService.instance.label().then((l) {
      if (mounted) setState(() => _saveLabel = l);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  String get _fileName {
    final t = _title.text.trim();
    final a = _artist.text.trim();
    if (t.isEmpty) return a;
    return a.isEmpty ? t : '$a - $t';
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.sub),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      );

  String _estimate(Duration? d) {
    if (d == null) return 'kbps';
    final mb = d.inSeconds * _bitrate * 1000 / 8 / 1024 / 1024;
    return 'kbps · about ${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB at $_bitrate';
  }

  void _start(VideoInfo info) {
    final guess = TagGuess.from(info.title, info.author);
    final title = _title.text.trim().isEmpty ? guess.title : _title.text.trim();
    final artist =
        _artist.text.trim().isEmpty ? guess.artist : _artist.text.trim();
    DownloadManager.instance.enqueue(
      info: info,
      bitrate: _bitrate,
      fileName: _fileName.isEmpty ? info.title : _fileName,
      tagTitle: title,
      tagArtist: artist,
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: FutureBuilder<VideoInfo>(
            future: _info,
            builder: (context, snap) {
              if (snap.hasError) {
                return _Message(
                  text: YoutubeService.friendlyError(snap.error!),
                  onClose: () => Navigator.pop(context),
                );
              }
              final info = snap.data;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Grabber(),
                  const SizedBox(height: 20),
                  _Header(info: info),
                  const SizedBox(height: 20),
                  const Text('QUALITY', style: sectionLabel),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final (i, q) in _qualities.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _QualityButton(
                            kbps: q.$1,
                            label: q.$2,
                            selected: _bitrate == q.$1,
                            onTap: () => setState(() => _bitrate = q.$1),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_estimate(info?.duration),
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _title,
                    onChanged: (_) => setState(() => _touched = true),
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 15),
                    decoration: _field('Title'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _artist,
                    onChanged: (_) => setState(() => _touched = true),
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 15),
                    decoration: _field('Artist'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.image_outlined,
                          size: 16, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Saved as "${StorageService.sanitizeFileName(_fileName)}.mp3" with cover art',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined,
                          size: 20, color: AppColors.muted),
                      const SizedBox(width: 10),
                      const Text('Save to', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      Text(_saveLabel,
                          style: const TextStyle(
                              fontSize: 15, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: info == null ? null : () => _start(info),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.bg,
                      disabledBackgroundColor: AppColors.surface2,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download MP3'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: AppColors.sub,
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 15)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF45484F),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.info});

  final VideoInfo? info;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 96,
            height: 54,
            color: AppColors.placeholder,
            child: info == null
                ? null
                : Image.network(info!.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: info == null
              ? const LinearProgressIndicator(minHeight: 2)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [info!.author, formatDuration(info!.duration)]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.kbps,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int kbps;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$kbps kbps, $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 72,
          decoration: BoxDecoration(
            color: selected ? AppColors.selectedFill : AppColors.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$kbps',
                  style: displayStyle(18,
                      weight: FontWeight.w600,
                      color: selected ? AppColors.accent : AppColors.text)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? const Color(0xFFD9DBC9)
                          : AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Grabber(),
        const SizedBox(height: 24),
        const Icon(Icons.error_outline_rounded,
            size: 36, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, height: 1.4)),
        const SizedBox(height: 20),
        TextButton(
          onPressed: onClose,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
