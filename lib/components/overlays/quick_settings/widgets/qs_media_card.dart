/*
Copyright 2026 The dahliaOS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:async';
import 'dart:io';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:pangolin/services/mpris.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// What a media player (MPRIS) plays, with its controls; nothing without a
/// player.
class QsMediaCard extends StatelessWidget {
  const QsMediaCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableServiceBuilder<MprisService>(
      builder: (context, _) {
        final MprisService service = MprisService.current;
        final MediaPlayer? player = service.player;
        if (player == null) return const SizedBox();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _MediaCard(player: player, players: service.players),
        );
      },
    );
  }
}

class _MediaCard extends StatefulWidget {
  const _MediaCard({required this.player, required this.players});

  final MediaPlayer player;
  final List<MediaPlayer> players;

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  /// Moves the seek bar along while playing (only while Quick Settings is
  /// open: the card exists only then).
  late final Timer _ticker;

  /// Where the seek bar is being dragged to.
  double? _dragging;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.player.playing && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  static String _time(Duration d) {
    final int minutes = d.inMinutes;
    final String seconds = (d.inSeconds % 60).toString().padLeft(2, "0");
    return minutes >= 60
        ? "${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, "0")}:$seconds"
        : "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MediaPlayer player = widget.player;
    final Color surface = theme.surfaceColor;
    final Color foreground = theme.computedForegroundColor(surface);
    final Color secondary = foreground.withValues(alpha: 0.65);
    final Duration? length = player.length;
    final Duration position = player.position;

    return Material(
      color: surface,
      shape: Constants.mediumShape,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Art(url: player.artUrl, size: 48, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.title.isEmpty ? player.identity : player.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                      Text(
                        player.artist.isEmpty
                            ? player.identity
                            : "${player.artist} · ${player.identity}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: secondary),
                      ),
                    ],
                  ),
                ),
                if (widget.players.length > 1)
                  PopupMenuButton<MediaPlayer>(
                    tooltip: "Switch player",
                    icon: Icon(Icons.swap_horiz_rounded, size: 18, color: secondary),
                    onSelected: MprisService.current.choose,
                    itemBuilder: (context) => [
                      for (final MediaPlayer p in widget.players)
                        PopupMenuItem(
                          value: p,
                          child: Text(
                            p.title.isEmpty ? p.identity : "${p.identity}: ${p.title}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (length != null && player.canSeek) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(_time(position), style: TextStyle(fontSize: 10, color: secondary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ZenitSlider(
                      // The card is the slider's usual track color.
                      trackColor: foreground.withValues(alpha: 0.12),
                      value: _dragging ??
                          (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0),
                      onChanged: (v) => setState(() => _dragging = v),
                      onChangeEnd: (v) {
                        setState(() => _dragging = null);
                        unawaited(player.seekTo(length * v));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_time(length), style: TextStyle(fontSize: 10, color: secondary)),
                ],
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: "Previous",
                  icon: Icon(Icons.skip_previous_rounded, color: foreground),
                  onPressed: player.canGoPrevious ? player.previous : null,
                ),
                const SizedBox(width: 8),
                Material(
                  color: theme.primaryColor,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: player.playing ? "Pause" : "Play",
                    icon: Icon(
                      player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: theme.computedForegroundColor(theme.primaryColor),
                    ),
                    onPressed: player.canPause || player.canPlay ? player.playPause : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: "Next",
                  icon: Icon(Icons.skip_next_rounded, color: foreground),
                  onPressed: player.canGoNext ? player.next : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover art from the player (a local file or a web address), else a note.
class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size, required this.color});

  final String? url;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = ColoredBox(
      color: color.withValues(alpha: 0.08),
      child: Icon(Icons.music_note_rounded, size: size / 2, color: color.withValues(alpha: 0.5)),
    );
    final Uri? uri = url == null ? null : Uri.tryParse(url!);
    final int cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget image = switch (uri?.scheme) {
      "file" => Image.file(
          File(uri!.toFilePath()),
          fit: BoxFit.cover,
          cacheWidth: cache,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      "http" || "https" => Image.network(
          url!,
          fit: BoxFit.cover,
          cacheWidth: cache,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      _ => placeholder,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(dimension: size, child: image),
    );
  }
}
