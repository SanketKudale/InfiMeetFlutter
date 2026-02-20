import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../theme/csn_theme.dart';
import '../theme/csn_theme_data.dart';
import '../utils/debug_log.dart';
import 'csn_call_controller.dart';
import 'csn_call_models.dart';

class CsnCallScreen extends StatefulWidget {
  const CsnCallScreen({
    super.key,
    required this.controller,
    this.themeOverride,
    this.onEndCall,
    this.padding = const EdgeInsets.all(16),
  });

  final CsnCallController controller;
  final CsnThemeData? themeOverride;
  final VoidCallback? onEndCall;
  final EdgeInsets padding;

  @override
  State<CsnCallScreen> createState() => _CsnCallScreenState();
}

class _CsnCallScreenState extends State<CsnCallScreen> {
  String? _lastErrorMessage;
  int _remoteQuarterTurns = 0;
  bool _remoteMirror = false;
  bool _autoExitHandled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void didUpdateWidget(CsnCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onUpdate);
      widget.controller.addListener(_onUpdate);
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    final errorMessage = widget.controller.state.errorMessage;
    if (errorMessage != null && errorMessage != _lastErrorMessage) {
      _lastErrorMessage = errorMessage;
      debugLog('Call error: $errorMessage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor:
              (widget.themeOverride ?? CsnTheme.of(context)).danger,
        ),
      );
    }
    setState(() {});
    if (!_autoExitHandled &&
        widget.controller.state.connectionState ==
            CsnCallConnectionState.ended) {
      _autoExitHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeOverride ?? CsnTheme.of(context);
    final state = widget.controller.state;

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Padding(
          padding: widget.padding,
          child: Column(
            children: [
              _TopBar(state: state, theme: theme),
              const SizedBox(height: 12),
              Expanded(
                child: _Grid(
                  participants: state.participants,
                  theme: theme,
                  remoteQuarterTurns: _remoteQuarterTurns,
                  remoteMirror: _remoteMirror,
                  onRotateRemote: () {
                    setState(() {
                      _remoteQuarterTurns = (_remoteQuarterTurns + 1) % 4;
                    });
                  },
                  onToggleRemoteMirror: () {
                    setState(() {
                      _remoteMirror = !_remoteMirror;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              _Controls(
                controller: widget.controller,
                theme: theme,
                onEndCall: widget.onEndCall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.theme});

  final CsnCallUiState state;
  final CsnThemeData theme;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (state.connectionState) {
      CsnCallConnectionState.connecting => 'Connecting?',
      CsnCallConnectionState.connected => 'Connected',
      CsnCallConnectionState.reconnecting => 'Reconnecting?',
      CsnCallConnectionState.ended => 'Ended',
      CsnCallConnectionState.error => state.errorMessage ?? 'Error',
      _ => 'Idle',
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Room ${state.roomId}',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: theme.mutedText),
              ),
            ],
          ),
        ),
        _Badge(
          label: '${state.participants.length} participants',
          color: theme.accent,
        ),
      ],
    );
  }
}

class _Grid extends StatefulWidget {
  const _Grid({
    required this.participants,
    required this.theme,
    required this.remoteQuarterTurns,
    required this.remoteMirror,
    required this.onRotateRemote,
    required this.onToggleRemoteMirror,
  });

  final List<CsnParticipant> participants;
  final CsnThemeData theme;
  final int remoteQuarterTurns;
  final bool remoteMirror;
  final VoidCallback onRotateRemote;
  final VoidCallback onToggleRemoteMirror;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  static const double _pipWidth = 110;
  static const double _pipHeight = 165;
  static const double _pipMargin = 12;
  double? _pipLeft;
  double? _pipTop;

  @override
  Widget build(BuildContext context) {
    if (widget.participants.isEmpty) {
      return _EmptyState(theme: widget.theme);
    }
    CsnParticipant? local;
    for (final p in widget.participants) {
      if (p.isLocal) {
        local = p;
        break;
      }
    }
    final remotes = widget.participants.where((p) => !p.isLocal).toList();

    if (remotes.isEmpty || local == null) {
      return _ParticipantTile(participant: widget.participants.first, theme: widget.theme);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLeft = (constraints.maxWidth - _pipWidth).clamp(0.0, double.infinity);
        final maxTop = (constraints.maxHeight - _pipHeight).clamp(0.0, double.infinity);
        final defaultLeft = (maxLeft - _pipMargin).clamp(0.0, maxLeft);
        final defaultTop = (maxTop - _pipMargin).clamp(0.0, maxTop);
        final left = (_pipLeft ?? defaultLeft).clamp(0.0, maxLeft);
        final top = (_pipTop ?? defaultTop).clamp(0.0, maxTop);

        return Stack(
          children: [
            Positioned.fill(
              child: _ParticipantTile(
                participant: remotes.first,
                theme: widget.theme,
                remoteQuarterTurns: widget.remoteQuarterTurns,
                remoteMirror: widget.remoteMirror,
                onRotateRemote: widget.onRotateRemote,
                onToggleRemoteMirror: widget.onToggleRemoteMirror,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: _pipWidth,
              height: _pipHeight,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final nextLeft = (left + details.delta.dx).clamp(0.0, maxLeft);
                  final nextTop = (top + details.delta.dy).clamp(0.0, maxTop);
                  setState(() {
                    _pipLeft = nextLeft;
                    _pipTop = nextTop;
                  });
                },
                child: _ParticipantTile(
                  participant: local!,
                  theme: widget.theme,
                  pip: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.theme,
    this.pip = false,
    this.remoteQuarterTurns = 0,
    this.remoteMirror = false,
    this.onRotateRemote,
    this.onToggleRemoteMirror,
  });

  final CsnParticipant participant;
  final CsnThemeData theme;
  final bool pip;
  final int remoteQuarterTurns;
  final bool remoteMirror;
  final VoidCallback? onRotateRemote;
  final VoidCallback? onToggleRemoteMirror;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(pip ? 12 : 16),
        border: Border.all(color: theme.mutedText.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(pip ? 12 : 16),
              child: participant.renderer != null && participant.videoEnabled
                  ? _VideoView(
                      participant: participant,
                      remoteQuarterTurns: remoteQuarterTurns,
                      remoteMirror: remoteMirror,
                    )
                  : _AvatarFallback(
                      name: participant.displayName, theme: theme),
            ),
          ),
          if (!participant.isLocal && !pip)
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onRotateRemote,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.rotate_right),
                    tooltip: 'Rotate remote',
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: onToggleRemoteMirror,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.flip),
                    tooltip: 'Mirror remote',
                  ),
                ],
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            right: 12,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    participant.displayName,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w600,
                      fontSize: pip ? 11 : 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusDot(
                    color: participant.audioEnabled
                        ? theme.success
                        : theme.danger),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoView extends StatelessWidget {
  const _VideoView({
    required this.participant,
    this.remoteQuarterTurns = 0,
    this.remoteMirror = false,
  });

  final CsnParticipant participant;
  final int remoteQuarterTurns;
  final bool remoteMirror;

  @override
  Widget build(BuildContext context) {
    final renderer = participant.renderer!;
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<RTCVideoValue>(
        valueListenable: renderer,
        builder: (context, value, _) {
          Widget view = RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: participant.isLocal ? true : remoteMirror,
          );

          if (participant.isLocal) return view;

          final normalizedRotation = ((value.rotation % 360) + 360) % 360;
          final hasSize = value.width > 0 && value.height > 0;
          final isPortraitBox = constraints.maxHeight >= constraints.maxWidth;
          final isLandscapeFrame = hasSize && value.width > value.height;
          final isPortraitFrame = hasSize && value.height > value.width;
          final needsFallbackQuarterTurn =
              (isPortraitBox && isLandscapeFrame) ||
                  (!isPortraitBox && isPortraitFrame);

          var autoTurns = ((normalizedRotation ~/ 90) % 4 + 4) % 4;
          if (normalizedRotation == 0 && needsFallbackQuarterTurn) {
            autoTurns = 1;
          }

          final manualTurns = ((remoteQuarterTurns % 4) + 4) % 4;
          final totalTurns = (autoTurns + manualTurns) % 4;
          if (!participant.isLocal && totalTurns != 0) {
            view = RotatedBox(
              quarterTurns: totalTurns,
              child: view,
            );
          }

          return view;
        },
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.theme});

  final String name;
  final CsnThemeData theme;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'U'
        : name
            .trim()
            .split(' ')
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();

    return Container(
      color: theme.background,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: theme.mutedText,
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls(
      {required this.controller, required this.theme, this.onEndCall});

  final CsnCallController controller;
  final CsnThemeData theme;
  final VoidCallback? onEndCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.mutedText.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: controller.localAudioEnabled ? Icons.mic : Icons.mic_off,
            label: controller.localAudioEnabled ? 'Mute' : 'Unmute',
            color: controller.localAudioEnabled ? theme.primary : theme.warning,
            onPressed: controller.toggleAudio,
          ),
          _ControlButton(
            icon: controller.localVideoEnabled
                ? Icons.videocam
                : Icons.videocam_off,
            label: controller.localVideoEnabled ? 'Video' : 'No Video',
            color: controller.localVideoEnabled ? theme.primary : theme.warning,
            onPressed: controller.toggleVideo,
          ),
          _ControlButton(
            icon: controller.screenSharingEnabled
                ? Icons.stop_screen_share
                : Icons.screen_share,
            label: controller.screenSharingEnabled ? 'Stop Share' : 'Share',
            color:
                controller.screenSharingEnabled ? theme.success : theme.accent,
            onPressed: controller.toggleScreenShare,
          ),
          _ControlButton(
            icon: Icons.cameraswitch,
            label: 'Switch',
            color: theme.accent,
            onPressed: controller.switchCamera,
          ),
          _ControlButton(
            icon: controller.speakerEnabled ? Icons.volume_up : Icons.hearing,
            label: controller.speakerEnabled ? 'Speaker' : 'Earpiece',
            color: theme.accent,
            onPressed: controller.toggleSpeaker,
          ),
          _ControlButton(
            icon: Icons.call_end,
            label: 'End',
            color: theme.danger,
            onPressed: () async {
              await controller.leave();
              onEndCall?.call();
            },
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          color: color,
          iconSize: 26,
          onPressed: () {
            unawaited(onPressed());
          },
        ),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final CsnThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No participants yet',
        style: TextStyle(color: theme.mutedText),
      ),
    );
  }
}
