import 'package:flutter/material.dart';

import '../api/models.dart';
import 'csn_request_controllers.dart';

Future<CsnSupportRequestType?> showCsnRequestModePicker(
  BuildContext context, {
  String title = 'How would you like support?',
  String videoCallLabel = 'Video Call',
  String videoCallSubtitle = 'Talk face to face with admin support.',
  String liveChatLabel = 'Live Chat',
  String liveChatSubtitle = 'Text chat one to one with admin support.',
}) {
  return showDialog<CsnSupportRequestType>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.videocam_rounded),
              title: Text(videoCallLabel),
              subtitle: Text(videoCallSubtitle),
              onTap: () {
                Navigator.of(dialogContext)
                    .pop(CsnSupportRequestType.videoCall);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_bubble_rounded),
              title: Text(liveChatLabel),
              subtitle: Text(liveChatSubtitle),
              onTap: () {
                Navigator.of(dialogContext).pop(CsnSupportRequestType.liveChat);
              },
            ),
          ],
        ),
      );
    },
  );
}

extension CsnUserRequestControllerModePicker on CsnUserRequestController {
  Future<CsnSupportRequestType?> pickAndSubmitRequestMode(
    BuildContext context, {
    String? userId,
    String title = 'How would you like support?',
    String videoCallLabel = 'Video Call',
    String videoCallSubtitle = 'Talk face to face with admin support.',
    String liveChatLabel = 'Live Chat',
    String liveChatSubtitle = 'Text chat one to one with admin support.',
  }) async {
    final selected = await showCsnRequestModePicker(
      context,
      title: title,
      videoCallLabel: videoCallLabel,
      videoCallSubtitle: videoCallSubtitle,
      liveChatLabel: liveChatLabel,
      liveChatSubtitle: liveChatSubtitle,
    );
    if (selected == null) return null;
    await submitRequest(userId: userId, requestType: selected);
    return selected;
  }
}
