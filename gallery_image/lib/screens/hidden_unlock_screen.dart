import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';

// PBKDF2-HMAC-SHA256 makes checking a guessed PIN more expensive. The media
// itself remains in the system library and is not encrypted by this feature.
String deriveHiddenLock(List<String> args) {
  final key = utf8.encode(args[0]);
  final salt = base64Decode(args[1]);
  final hmac = Hmac(sha256, key);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = Uint8List.fromList(block);
  for (var i = 1; i < 100000; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return base64Encode(result);
}

Future<bool> unlockHiddenAlbum(BuildContext context) async {
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const HiddenUnlockScreen()),
      ) ??
      false;
}

Future<bool> changeHiddenAlbumLock(BuildContext context) async {
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const HiddenUnlockScreen(replaceExisting: true),
        ),
      ) ??
      false;
}

class HiddenUnlockScreen extends StatefulWidget {
  const HiddenUnlockScreen({super.key, this.replaceExisting = false});

  final bool replaceExisting;

  @override
  State<HiddenUnlockScreen> createState() => _HiddenUnlockScreenState();
}

class _HiddenUnlockScreenState extends State<HiddenUnlockScreen>
    with WidgetsBindingObserver {
  final storage = GetStorage();
  final pin = TextEditingController();
  final pattern = <int>[];
  String? type;
  String? firstEntry;
  String? error;
  bool busy = false;
  bool cancelled = false;
  bool get hasLock => storage.read<Map>('hidden_album_lock') != null;
  bool get settingLock => widget.replaceExisting || !hasLock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.replaceExisting) {
      type = storage.read<Map>('hidden_album_lock')?['type'] as String?;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        mounted &&
        !cancelled) {
      cancelled = true;
      Navigator.of(context).pop(false);
    }
  }

  Future<void> submit(String value) async {
    if (busy || type == null) return;
    final valid = type == 'pattern'
        ? value.length >= 4
        : RegExp(type == 'pin4' ? r'^\d{4}$' : r'^\d{6}$').hasMatch(value);
    if (!valid) {
      setState(
        () => error = type == 'pattern'
            ? 'Connect at least 4 dots.'
            : 'Enter the required number of digits.',
      );
      return;
    }
    if (settingLock && firstEntry == null) {
      setState(() {
        firstEntry = value;
        error = null;
        pin.clear();
        pattern.clear();
      });
      return;
    }
    if (settingLock && value != firstEntry) {
      setState(() {
        firstEntry = null;
        error = 'Entries did not match. Please start again.';
        pin.clear();
        pattern.clear();
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final lock = storage.read<Map>('hidden_album_lock');
      final salt = settingLock
          ? base64Encode(
              List<int>.generate(16, (_) => Random.secure().nextInt(256)),
            )
          : lock!['salt'] as String;
      final hash = await compute(deriveHiddenLock, [value, salt]);
      if (!mounted || cancelled) return;
      if (settingLock) {
        await storage.write('hidden_album_lock', {
          'type': type,
          'salt': salt,
          'hash': hash,
        });
      } else if (hash != lock!['hash']) {
        if (mounted) {
          setState(() {
            error = 'Incorrect lock. Try again.';
            pin.clear();
            pattern.clear();
          });
        }
        return;
      }
      if (mounted && !cancelled) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not access the lock. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void addPoint(Offset position, double size) {
    final cell = size / 3;
    final col = (position.dx / cell).floor();
    final row = (position.dy / cell).floor();
    if (col < 0 || col > 2 || row < 0 || row > 2) return;
    final center = Offset((col + .5) * cell, (row + .5) * cell);
    final index = row * 3 + col;
    if ((position - center).distance < cell * .35 && !pattern.contains(index)) {
      setState(() => pattern.add(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.replaceExisting
              ? 'Set a new lock'
              : hasLock
              ? 'Unlock hidden album'
              : 'Set up hidden album',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settingLock) ...[
                    const Text(
                      'Hidden items are only hidden in this app. They remain visible in other gallery apps and are not encrypted. If you forget this lock, it cannot be recovered.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'Lock type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pin4',
                          child: Text('4-digit PIN'),
                        ),
                        DropdownMenuItem(
                          value: 'pin6',
                          child: Text('6-digit PIN'),
                        ),
                        DropdownMenuItem(
                          value: 'pattern',
                          child: Text('Pattern'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              type = value;
                              firstEntry = null;
                              pin.clear();
                              pattern.clear();
                              error = null;
                            }),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (type != null) ...[
                    Text(
                      !settingLock
                          ? 'Enter your ${type == 'pattern' ? 'pattern' : 'PIN'}'
                          : firstEntry == null
                          ? 'Choose your ${type == 'pattern' ? 'pattern' : 'PIN'}'
                          : 'Confirm your ${type == 'pattern' ? 'pattern' : 'PIN'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (type == 'pattern')
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final size = min(constraints.maxWidth, 280.0);
                          return GestureDetector(
                            onPanStart: busy
                                ? null
                                : (details) {
                                    setState(pattern.clear);
                                    addPoint(details.localPosition, size);
                                  },
                            onPanUpdate: busy
                                ? null
                                : (details) =>
                                      addPoint(details.localPosition, size),
                            onPanEnd: busy
                                ? null
                                : (_) => submit(pattern.join()),
                            child: CustomPaint(
                              size: Size.square(size),
                              painter: _PatternPainter(
                                List.of(pattern),
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      TextField(
                        controller: pin,
                        enabled: !busy,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                            type == 'pin4' ? 4 : 6,
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'PIN',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: submit,
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (busy)
                      const CircularProgressIndicator()
                    else if (type != 'pattern')
                      FilledButton(
                        onPressed: () => submit(pin.text),
                        child: const Text('Continue'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.points, this.color, this.inactiveColor);
  final List<int> points;
  final Color color;
  final Color inactiveColor;
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 3;
    Offset point(int i) => Offset((i % 3 + .5) * cell, (i ~/ 3 + .5) * cell);
    final line = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(point(points[i - 1]), point(points[i]), line);
    }
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(
        point(i),
        points.contains(i) ? 12 : 8,
        Paint()..color = points.contains(i) ? color : inactiveColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) =>
      !listEquals(points, oldDelegate.points) ||
      color != oldDelegate.color ||
      inactiveColor != oldDelegate.inactiveColor;
}
