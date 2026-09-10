# HyperDrop ⚡ — High-Speed Hybrid Local & P2P Transfer Engine

<div align="center">

**Lightning-fast, peer-to-peer file sharing designed for cross-device transfer.**
*Engineered for maximum local hardware bandwidth utilization without cloud dependencies.*

[![GitHub Release](https://img.shields.io/badge/Release-v2.0.0-00f2fe.svg)](https://github.com/sandeepsagar18/HyperDrop)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Linux-00ff87.svg)](https://github.com/sandeepsagar18/HyperDrop)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## ⚡ Core Transfer Modes

### ⚡ Adaptive Binary Chunk Streaming (10GB+ Files)
Supports massive 4K videos, large archives, and multi-gigabyte project directories using dynamic 2MB–16MB chunk streaming with zero RAM bloat and random-access disk ingestion.

### 📱 Mobile Hotspot & Offline Mode
No router available? Connect phones directly through a mobile hotspot with zero internet connection or cellular data required.

### 🚀 Line-Rate Hardware Speeds (50–90+ MB/s)
Pipelined socket streaming maximizes Wi-Fi 5/6 and mobile hotspot line-rate throughput for rapid file migration.

### 🔒 Direct & End-to-End Private
Files stream directly between peer devices over local socket channels with SHA-256 integrity verification rather than routing through third-party servers.

---

## 🌟 Key Features

- **⚡ Adaptive Binary Chunk Streaming (10GB+ Files)**:
  - Dynamic 2MB–16MB chunks with random-access disk writes (`fs.writeSync`) supporting 100GB+ transfers with low memory footprint.
  - Resume interrupted transfers from exact chunk offsets.
- **📁 Queue-Controlled Batch Folder Transfers**:
  - Drag-and-drop entire directory trees with automatic concurrency control and root folder grouping.
- **📥 Interactive Download Confirmation & File Explorer Opener**:
  - Media badge icons (4K Video, Image, Audio, PDF) and automatic dual-saving to the system `Downloads` folder.
  - 1-Click **"Open in Folder"** button highlights downloaded files directly in Windows File Explorer.
- **📱 💻 Fluid Cyberpunk Responsive Layout**:
  - Seamlessly adapts across widescreen monitors, laptops, tablets, and mobile devices with glowing orbital radar.
- **🛰️ Automated Radar & Subnet Discovery**:
  - Dual UDP broadcast beacon (port 35432) + active ARP subnet probing automatically detects nearby phones and laptops.
- **📷 Instant QR Code Pairing**:
  - Scan the dynamic QR code directly from any mobile camera to pair and stream files instantly without app installation.
- **⚡ Real-Time Speedometer & Metric Controls**:
  - Live throughput gauge (MB/s & Mbps), peak speed tracker, ETA calculator, and 1-click **Cancel** / **Restart** controls.
- **📦 Data Vault & In-App Media Viewer**:
  - Built-in secure offline vault with SHA-256 hash checks and integrated players for 4K Videos, Images, Audio, and PDFs.
- **📋 Instant Text & Clipboard Sync**:
  - Synchronize notes, code snippets, and URLs in real-time across all paired devices.
- **📦 Standalone 1-Click Windows Setup (`HyperDrop-Setup.exe`)**:
  - Native Windows installer with automatic process release guards and desktop shortcut creation.

---

## 🛠️ Architecture & Tech Stack

| Layer | Technologies |
|---|---|
| **Windows Desktop App** | Flutter 3.x, Dart, Riverpod 2.x, Win32 Native API, WebView Windows |
| **Backend Engine** | Node.js, Express, WebSocket, UDP Broadcast Engine, Multi-Worker Pool |
| **Web Frontend** | Vanilla ES6+ JavaScript, Responsive CSS Grid/Flexbox, Offline FontAwesome Icon Suite |
| **Network Protocols** | TCP Chunk Streaming, UDP Subnet Beacons, WebSockets, WebRTC DataChannels, ARP Scanner |

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

### 2. Windows Desktop Application

#### Option A: 1-Click Installer
Run `HyperDrop-Setup.exe` to automatically install the release application and create desktop shortcuts.

#### Option B: Build from Source with Flutter
```bash
cd flutter

# Get dependencies
flutter pub get

# Run on Windows
flutter run -d windows

# Build Release Executable
flutter build windows --release
```

The compiled release binary will be generated at:
```
flutter/build/windows/x64/runner/Release/hyperdrop_flutter.exe
```

---

### 3. Android Mobile Application

#### Option A: Direct APK Install
The signed release APK can be installed directly onto any Android device:
```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

#### Option B: Build from Source
```bash
cd android
./gradlew assembleDebug
```
The output APK will be generated at:
```
android/app/build/outputs/apk/debug/app-debug.apk
```

---

## 🔒 Network & Firewall Setup

If other devices on your Wi-Fi network cannot reach the laptop on port `3000`:
1. Right-click on **`fix_firewall_run_as_admin.bat`** in the root directory.
2. Select **"Run as administrator"**.
3. Ensure your Windows Wi-Fi Network Profile is set to **Private**.

---

## 👨‍💻 Author

**Built with ❤️ by Sandeep**
- **GitHub:** [@sandeepsagar18](https://github.com/sandeepsagar18)
- **Repository:** [HyperDrop](https://github.com/sandeepsagar18/HyperDrop)

