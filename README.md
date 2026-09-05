# ozo-app

A cross-platform, local-first communication app (inspired by Telegram) that operates entirely over a local area network (LAN / Wi-Fi) without requiring internet connectivity or any external cloud server.

Built with **Flutter (Dart)** from a **single codebase** targeting **Windows, macOS, Linux, Android, and iOS**.

---

## 🚀 Key Features

- **Real-Time Direct & Group Messaging**: Full-duplex WebSocket communication between peers on the same local network.
- **Broadcast-First Auto Discovery**:
  - Automatically discovers other devices on the LAN using UDP broadcast to `255.255.255.255` and subnet-directed broadcasts (e.g. `192.168.1.255`).
  - Soft-fail multicast enhancement (`224.0.0.167`) that runs without requiring Apple's restricted multicast entitlement.
- **Resumable Chunked File Transfer**:
  - Transfer any file type with 512 KB chunking.
  - HTTP Range headers (`Range: bytes={offset}-`) allow pausing and resuming transfers from any byte offset if connection drops.
  - End-to-end SHA-256 checksum verification upon completion.
  - Real-time transfer speed (MB/s) and progress indicators.
- **Host-Relay Group Chat Architecture**:
  - Group creator acts as Host, relaying messages to avoid $O(n^2)$ full-mesh connection churn on mobile devices.
  - Automatic read-only fallback with warning banner if the group host goes offline.
- **End-to-End Encryption (E2EE) & TOFU Anti-Spoofing**:
  - **X25519 ECDH** key agreement for ephemeral shared secrets.
  - **ChaCha20-Poly1305 AEAD** authenticated encryption for messages and file streams.
  - **Trust-On-First-Use (TOFU)** key pinning: flags `⚠️ Identity Changed (Possible Impersonation)` if a peer's public key changes for a known device ID.
  - **Safety Numbers Screen**: Compare 8-character cryptographic safety fingerprints (e.g. `A1B2-C3D4`) in person.
- **Local Persistent Storage**:
  - Message history, discovered peer history, and group memberships stored locally on device.
- **AP-Isolation & Network Diagnostics**:
  - Built-in diagnostic card and topology guide when zero peers are found (detecting router Client/AP isolation on guest/hotel Wi-Fi).
- **Telegram Adaptive UI**:
  - Responsive 2-column split layout for Desktop and Tablets; fluid navigation stack for Mobile.
  - Light & dark themes with authentic Telegram styling.

---

## 🛠 Tech Stack

| Layer | Technology |
| :--- | :--- |
| **Framework** | Flutter 3.x (Dart 3.x) |
| **P2P Transport** | Embedded `HttpServer` & `WebSocket` daemon (`dart:io`) on port `45455` |
| **Discovery** | UDP Broadcast + Multicast on port `45454` (`network_info_plus`, `dart:io`) |
| **Encryption** | `cryptography` (X25519, ChaCha20-Poly1305, Ed25519) |
| **Integrity & Hashing** | `crypto` (SHA-256 checksums) |
| **File Picker** | `file_picker` (Native desktop & mobile integration) |
| **State Management** | `provider` |

---

## 📦 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.24+ recommended)
- Git

### Installation
```bash
# Clone the repository
git clone https://github.com/Heng-zm/ozo-app.git
cd ozo-app

# Fetch dependencies
flutter pub get
```

### Running the App
```bash
# Run on Windows
flutter run -d windows

# Run on macOS
flutter run -d macos

# Run on Linux
flutter run -d linux

# Run on Android
flutter run -d android

# Run on iOS
flutter run -d ios
```

### Testing
Run the complete automated test suite (11 unit, crypto, protocol, and integration tests):
```bash
flutter test
```

Verify static analysis:
```bash
flutter analyze
```

---

## 🌐 Network Requirements
1. Devices must be connected to the **same local network / Wi-Fi subnet**.
2. **Client/AP Isolation** must be turned off in the Wi-Fi router settings (some public/hotel guest Wi-Fi blocks peer-to-peer traffic).

---

## 📄 License
MIT License
