# Changelog

## 0.3.2

- Added complete executive management from admin:
  - create executive
  - activate/deactivate executive
  - reset executive password
  - delete executive
- Added admin self password change flow.
- Added dedicated `Manage Executives` page in the example app with cleaner row layout and one-line action controls.
- Improved call stability by avoiding immediate teardown on transient peer-connection failure and adding recovery offer flow.
- Hardened media/dialog cleanup paths to prevent disposed-controller and disposed-track runtime exceptions.

## 0.3.1

- Updated video call UI: local user PiP tile is now draggable and can be positioned anywhere on screen during an active call.
- This drag behavior applies to the local user tile only.

## 0.3.0

- Added live chat support in SDK UI:
  - `CsnLiveChatController`
  - `CsnLiveChatScreen`
  - exported from `csn_flutter.dart`.
- Added queue item request type handling (`video_call` / `live_chat`) in admin queue models.
- Updated example app executive flow:
  - request-type aware accept handling
  - opens live chat UI for live chat requests.
- Added Android media projection bridge/service integration for screen sharing compatibility.
- Improved call and chat end behavior:
  - immediate call end on peer closed/disconnected/failed states
  - synchronized live chat close across both participants.
- Updated OTT integration compatibility with local package path + live chat accepted flow support.

## 0.2.0

- Added support request type selection with popup helper:
  - `showCsnRequestModePicker(...)`
  - `pickAndSubmitRequestMode(...)`
  - request types: `video_call` and `live_chat`.
- Added role-based backend auth models and API methods:
  - admin/executive login support
  - executive list/create support
  - admin and executive history fetch support.
- Updated request queue/action API paths for executive role workflows.
- Added automatic signaling reconnect with periodic keepalive ping for better realtime reliability.
- Added one-to-one end synchronization support:
  - user-side request end API client method
  - automatic call UI exit when call/request is ended remotely.
- Added screen sharing support in video calls:
  - new call controller APIs:
    - `screenSharingEnabled`
    - `toggleScreenShare()`
  - new share/stop-share control in `CsnCallScreen`.
- Improved end-call behavior so both participants are terminated consistently when session closes.

## 0.1.1

- Fixed remote participant video orientation handling in `CsnCallScreen`.
- Added robust remote correction support for rotation/mirroring across mixed devices.
- Removed rotation artifacts that could cause white bars around remote video.

## 0.1.0

- Initial public release.
- Added CSN API client and signaling client.
- Added user/admin request queue controllers.
- Added prebuilt call controller and call screen UI.
- Added configurable CSN theming.
