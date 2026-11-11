import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/media_utils.dart';

class VideoTransport extends StatefulWidget {
  const VideoTransport({
    super.key,
    required this.player,
    required this.onTogglePlayback,
    required this.onSeekBy,
  });

  final VideoPlayerController player;
  final VoidCallback onTogglePlayback;
  final Future<void> Function(int seconds) onSeekBy;

  @override
  State<VideoTransport> createState() => _VideoTransportState();
}

class _VideoTransportState extends State<VideoTransport> {
  bool dragging = false;
  double dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
        final positionMs = dragging
            ? dragValue
            : value.position.inMilliseconds.toDouble();
        final shownPosition = dragging
            ? Duration(milliseconds: dragValue.round())
            : value.position;

        return Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  onPressed: widget.onTogglePlayback,
                  icon: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: positionMs.clamp(0.0, maxMs).toDouble(),
                    max: maxMs,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: durationMs > 0
                        ? (newValue) {
                            setState(() {
                              dragging = true;
                              dragValue = newValue;
                            });
                          }
                        : null,
                    onChangeEnd: durationMs > 0
                        ? (newValue) async {
                            await player.seekTo(
                              Duration(milliseconds: newValue.round()),
                            );
                            if (!mounted) return;
                            setState(() => dragging = false);
                          }
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                  onPressed: () => player.setVolume(value.volume == 0 ? 1 : 0),
                  icon: Icon(
                    value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  formatMediaDuration(shownPosition.inSeconds),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: () => widget.onSeekBy(-10),
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: () => widget.onSeekBy(10),
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  formatMediaDuration(value.duration.inSeconds),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
