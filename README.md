# HyperDrop ⚡ — High-Speed Hybrid Local & P2P Transfer Engine

<div align="center">

**Lightning-fast, peer-to-peer file sharing designed for cross-device transfer.**
*Engineered for maximum local hardware bandwidth utilization without cloud dependencies.*

[![GitHub Release](https://img.shields.io/badge/Release-v1.0.0-00f2fe.svg)](https://github.com/sandeepsagar18/HyperDrop)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Linux-00ff87.svg)](https://github.com/sandeepsagar18/HyperDrop)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## ⚡ Core Transfer Modes

### ⚡ Local Wi-Fi Transfer
Transfer files directly between devices connected to the same Wi-Fi network without uploading files to a cloud storage server.

### 📱 Mobile Hotspot Mode
No router available? Connect devices directly through a mobile hotspot with zero internet connection required.

### 🚀 High-Speed Multi-Worker Transfer Engine
Utilizes available local network bandwidth for gigabit-speed transfers, including multi-gigabyte files and complete directory structures.

### 🔒 Direct & End-to-End Private
Files stream directly between peer devices over local socket channels rather than routing through intermediary servers.

---

## 🌟 Key Features

- **📱 💻 100% Fluid Responsive Layout**:
  - Seamlessly adapts across widescreen monitors, laptops, tablets, and mobile devices.
  - Multi-column dashboard grid with an expanded **Data Vault & Storage** view.
  - Cyberpunk dark theme with glowing neon accents and orbital radar interface.
- **🛰️ Automated Radar & Subnet Discovery**:
  - Dual UDP broadcast + active ARP LAN subnet probing automatically detects nearby phones and laptops.
  - Real-time orbital radar displays connected device nodes with interactive status badges.
- **📷 Instant QR Code Pairing**:
  - Scan the dynamic QR code on the dashboard directly from any mobile camera to pair and stream files instantly.
- **⚡ Live Transfer Speedometer & Metric Controls**:
  - Real-time speedometer gauge displaying transfer throughput in MB/s.
  - 1-Click **Cancel** and **Restart** controls for active file transfers.
  - Metrics tracking: **Peak Speed**, **Active Streaming Channels**, **Total Transferred**, and **ETA**.
- **📦 Data Vault & In-App Media Viewer**:
  - Built-in secure offline vault with SHA-256 integrity verification.
  - Built-in instant preview players for Images, Videos, Audio, and PDFs.
- **📋 Instant Text & Clipboard Sync**:
  - Send clipboard notes, links, and messages instantly across all connected devices.
- **📦 Windows Setup Wizard (`HyperDrop-Setup.exe`)**:
  - Native standalone 1-click Windows installer packaging the high-performance release binary and desktop shortcuts.

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
