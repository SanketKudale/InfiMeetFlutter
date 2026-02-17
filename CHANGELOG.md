# Changelog

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
