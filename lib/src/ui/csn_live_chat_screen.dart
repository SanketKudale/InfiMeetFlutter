import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/csn_theme.dart';
import 'csn_live_chat_controller.dart';

class CsnLiveChatScreen extends StatefulWidget {
  const CsnLiveChatScreen({
    super.key,
    required this.controller,
    this.title = 'Live Chat',
    this.onEndChat,
  });

  final CsnLiveChatController controller;
  final String title;
  final Future<void> Function()? onEndChat;

  @override
  State<CsnLiveChatScreen> createState() => _CsnLiveChatScreenState();
}

class _CsnLiveChatScreenState extends State<CsnLiveChatScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  bool _wasConnected = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.connect());
    });
  }

  void _onUpdate() {
    if (!mounted) return;
    if (widget.controller.connected) {
      _wasConnected = true;
    }
    setState(() {});
    if (_wasConnected && !widget.controller.connected) {
      unawaited(_closeChatAndExit(endRequest: false));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CsnTheme.of(context);
    final messages = widget.controller.messages;
    return PopScope(
      canPop: !_closing,
      onPopInvokedWithResult: (_, __) {
        if (_closing) return;
        unawaited(_closeChatAndExit());
      },
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: () {
                unawaited(_closeChatAndExit());
              },
              child: const Text('End'),
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.controller.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.red.withValues(alpha: 0.15),
                child: Text(
                  widget.controller.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final item = messages[index];
                  final mine = item.senderId == widget.controller.localUserId;
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: mine
                            ? theme.primary.withValues(alpha: 0.2)
                            : theme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          Text(item.text, style: TextStyle(color: theme.text)),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        decoration: const InputDecoration(
                          hintText: 'Type message...',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.controller.sendMessage(text);
    _input.clear();
  }

  Future<void> _closeChatAndExit({bool endRequest = true}) async {
    if (_closing) return;
    _closing = true;
    final navigator = Navigator.of(context);
    await widget.controller.leave();
    if (endRequest) {
      await widget.onEndChat?.call();
    }
    if (!mounted) return;
    navigator.maybePop();
  }
}
