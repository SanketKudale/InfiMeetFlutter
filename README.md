# CSN Flutter SDK

Flutter SDK for CSN realtime calling flows:
- user request queue
- admin accept/decline
- prebuilt call screen
- API + WebSocket signaling clients

## Important: Backend Requirement

This Flutter SDK requires the CSN Node backend to work.

The backend is provided separately as a paid product.

For backend access and licensing:
`sksanketkudale@gmail.com`

## Installation

Add this package in your app `pubspec.yaml`:

```yaml
dependencies:
  csn_flutter: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

Create SDK:

```dart
final sdk = CsnSdk(
  baseUrl: 'http://<your-server>:6713',
  wsUrl: 'ws://<your-server>:6713/ws',
  jwt: '<access-token>',
);
```

Initialize a call controller:

```dart
final controller = CsnBasicCallController(
  apiClient: sdk.api,
  signalingClient: sdk.signaling(),
  localUserId: 'user-1',
);

await controller.initialize();
await controller.join('room-id');
```

Open prebuilt call screen:

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => CsnCallScreen(controller: controller),
  ),
);
```

## Included Modules

- `CsnApiClient`
- `CsnSignalingClient`
- `CsnUserRequestController`
- `CsnAdminRequestController`
- `CsnBasicCallController`
- `CsnCallScreen`
- `csnTheme` / `CsnThemeData`

## Backend Purchase / Support

For backend purchase, setup, and production deployment support:
`sksanketkudale@gmail.com`
