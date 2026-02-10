# CSN Flutter SDK

A reusable Flutter package to talk to the CSN audio/video calling backend.

## Install
Add this package to your app `pubspec.yaml` (path dependency while local):

```
dependencies:
  csn_flutter:
    path: ../csn_flutter
```

## Usage

### Create SDK
```
final sdk = CsnSdk(
  baseUrl: 'http://localhost:3000',
  wsUrl: 'ws://localhost:3000/ws',
  jwt: '<your-jwt>',
);
```

### Theme (configurable)
```
return MaterialApp(
  theme: csnTheme(
    brightness: Brightness.light,
    override: CsnThemeData.light().copyWith(
      primary: Colors.indigo,
      accent: Colors.teal,
    ),
  ),
);
```

### Call UI (prebuilt)
```
final controller = CsnBasicCallController(
  apiClient: sdk.api,
  signalingClient: sdk.signaling(),
  localUserId: 'user-1',
);

await controller.initialize();
await controller.join('room-1');

Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => CsnCallScreen(controller: controller),
  ),
);
```

## Notes
- This package wires API + signaling. It does not include a mediasoup client; for real media, integrate flutter_webrtc + mediasoup client logic.
- WebSocket signaling protocol is described in your backend docs.
