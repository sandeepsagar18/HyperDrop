# HyperDrop ⚡ — High-Speed Hybrid Local & P2P Transfer Engine

**HyperDrop** is a peer-to-peer file transfer engine designed for fast, seamless cross-device sharing. Engineered for maximum local hardware bandwidth utilization without relying on cloud storage servers.

---

## ⚡ Core Transfer Modes

### ⚡ Local Wi-Fi Transfer
Transfer files directly between devices connected to the same Wi-Fi network — without uploading your files to a cloud server.

### 📱 Mobile Hotspot Mode
No router? No problem. Connect devices directly through a mobile hotspot with zero internet connection required.

### 🚀 High-Speed File Transfer Engine
HyperDrop is designed to utilize available local network bandwidth for ultra-fast transfers, including multi-gigabyte files and entire folder directories.

### 🔒 Direct & Private
Files are transferred directly between connected devices rather than being routed through a central cloud storage server.

---

## 🌟 Key Features

- **Cross-Platform Parity**:
  - 🖥️ **Windows Desktop App** built with **Flutter & Riverpod** (64-bit native high-performance executable).
  - 📱 **Mobile & Web Client** (Zero-install web client for Android, iPhone, iPad, macOS, Linux).
- **Automated Radar Discovery**:
  - Dual UDP broadcast + background poll engine automatically detects nearby devices on your local network.
  - Interactive orbital radar showing live device nodes.
- **Dynamic QR Connect**:
  - Scan the dynamic QR code directly from your phone camera to instantly connect and transfer files.
- **Live Transfer Engine & Speedometer**:
  - Live speedometer gauge measuring real-time transfer throughput in MB/s.
  - 1-Click **Cancel** and **Restart** controls positioned side-by-side.
  - Live metrics: Peak Speed, Active Channels, Total Data Moved, and ETA.
- **App Data Vault & Previewer**:
  - Built-in secure offline vault with SHA-256 integrity verification.
  - Instant file previews for Images, Audio, Videos, and PDFs.
- **Instant Text & Clipboard Sync**:
  - Send clipboard text, links, and messages seamlessly across all connected devices.
- **Privacy-Preserving Feedback System**:
  - Built-in feedback integration directly launching user email client without exposing recipient addresses.

---

## 🛠️ Architecture & Tech Stack

| Layer | Technologies |
|---|---|
| **Flutter Desktop App** | Flutter 3.x, Dart, Riverpod 2.x, Win32 Native API, Network Info Plus |
| **Backend & Engine** | Node.js, Express, WebSocket, UDP Broadcast Engine, Multi-Worker Pool |
| **Web Frontend** | Vanilla ES6+ JavaScript, CSS3 Cyber Dark Theme, Offline SVG Icon Pack |
| **Network Protocols** | TCP Chunk Streaming, UDP Peer Pulse, WebSockets, WebRTC DataChannels |

---

## 🚀 Quick Start Guide

### 1. Web & Node.js Engine

#### Prerequisites
- [Node.js](https://nodejs.org/) (v16 or higher)

#### Run Server
```bash
# Clone the repository
git clone https://github.com/sandeepsagar18/HyperDrop.git
cd HyperDrop

# Install dependencies
npm install

# Start the HyperDrop engine
npm start
```

Access the interface:
- **Local Machine:** `http://localhost:3000`
- **Mobile Devices on Same Wi-Fi:** `http://<your-local-ip>:3000`

---

### 2. Flutter Desktop Application (Windows)

#### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0+)

#### Build & Run
```bash
cd flutter

# Get Flutter packages
flutter pub get

# Run on Windows
flutter run -d windows

# Or build debug / release executable
flutter build windows --debug
```

The compiled binary will be located at:
```
flutter/build/windows/x64/runner/Debug/hyperdrop_flutter.exe
```

---

## 🔒 Network & Firewall Configuration

If other devices on your Wi-Fi cannot reach the server on port `3000`:
1. Right-click on **`fix_firewall_run_as_admin.bat`** in the root directory.
2. Select **"Run as administrator"**.
3. Ensure your Windows Wi-Fi Network Profile is set to **Private**.

---

## 👨‍💻 Author

**Built with ❤️ by Sandeep**
- **Repository:** [sandeepsagar18/HyperDrop](https://github.com/sandeepsagar18/HyperDrop)
