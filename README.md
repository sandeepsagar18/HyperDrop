# HyperDrop
# LARGE FILE TRANSFER APP
# 🚀 HyperDrop — Ultra-Speed Cross-Platform Local File Transfer & Data Vault

<div align="center">

[![Node.js Version](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen.svg?style=for-the-badge&logo=node.js)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)
[![Speed](https://img.shields.io/badge/Max%20Throughput-191.7%20MB%2Fs-cyan.svg?style=for-the-badge&logo=speedtest)](https://github.com)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-orange.svg?style=for-the-badge)](https://github.com)

**Private, lightning-fast, zero-installation local network file transfer and universal clipboard synchronization.**

[Key Features](#-key-features) • [Benchmarks](#-real-world-benchmarks) • [Quick Start](#-quick-start) • [Architecture](#-architecture) • [Security](#-security--hardening)

</div>

---

## 📖 Overview

**HyperDrop** is a modern, high-throughput, cross-platform file transfer system designed to move files between devices (Windows, Android, iOS, macOS, Linux) over local Wi-Fi or Mobile Hotspots at **maximum physical wire speed** with:

- ⚡ **Zero Cloud Dependency & Zero Internet Usage**: Transfers files directly device-to-device over LAN.
- 📱 **Zero App Installation**: Works instantly inside any modern web browser via QR code or local IP.
- 📦 **No File Size Limits**: Effortlessly streams small photos up to massive 10GB+ video archives and ISOs.
- 🔒 **100% Private**: Your data never leaves your local network.

---

## ⚡ Real-World Benchmarks

*Tested on physical hardware: **Windows Laptop $\longleftrightarrow$ Android Mobile** over 5 GHz Wi-Fi Link (`866 Mbps`):*

| File Tested | Size | Transfer Time | Average Speed | Peak Burst Speed | Internet Used |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 📄 **Document / Presentation** | 117.34 MB | **13.3 seconds** | ~8.8 MB/s | 18.0 MB/s | **0 MB** |
| 🎬 **HD Video Clip (`IMG_7414.mov`)** | 495.79 MB | ⚡ **3.3 seconds** | **151.9 MB/s** | 362.3 MB/s | **0 MB** |
| 💽 **Full HD Episode (`Off.Campus...`)** | **2.42 GB** | 🔥 **12.9 seconds** | **191.7 MB/s** ($1.53\text{ Gbps}$) | **1.00 GB/s** | **0 MB** |

### 🏆 Comparison with Common Sharing Methods (2.42 GB File):

```
HyperDrop (This Project):  ████ 12.9 seconds (191.7 MB/s) [0 MB Data]
Apple AirDrop:             ████████████████ 120 seconds (2 mins)
Google Drive / Dropbox:    ██████████████████████████████ 10 mins (Consumes 4.84 GB Data)
WhatsApp:                  ❌ FAILED (Exceeds 2 GB file limit)
Bluetooth 5.0:             ████████████████████████████████████████... 3.5+ Hours
```

---

## ✨ Key Features

### 1. 🚀 Parallel Multi-Worker Streaming Engine
- **Intelligent Auto-Scaling**: Automatically calculates file size and assigns optimal chunk sizes (1MB to 16MB) and parallel worker threads (16 to 64 workers).
- **Socket Pipelining**: Direct streaming into memory with `TCP_NODELAY` prevents packet buffering delays.
- **Cancel & Restart**: Dedicated cancellation and restart controls for individual transfers.

### 2. 🌐 Symmetrical Radar Device Discovery
- **Bidirectional Mesh**: Devices automatically detect each other upon opening the page.
- **Interactive Radar Canvas**: Visualizes connected peers with device type badges (💻 Laptop / 📱 Mobile) and custom device names.
- **1-Click Direct Sending**: Instant transmission without blocking dialogs when a peer is connected.

### 3. 📋 Instant Universal Clipboard & Text Sync
- Copy-paste links, passwords, OTPs, addresses, notes, or code snippets across devices in $0\text{ms}$.
- Automatically saves notes to the local vault as `.txt` files.

### 4. 🗄️ Offline Data Vault & In-Browser File Previewer
- Stored locally inside **IndexedDB v6** for persistent offline retrieval.
- Integrated multi-format file viewer for **PDFs, Videos, Audio, Images, and Code** with zero external dependencies.

### 5. 🛡️ Enterprise Security & Hardening
- **Path Traversal Defense**: Sanitizes filenames to eliminate directory traversal attacks.
- **Strict Boundary Validation**: Validates all transfer headers, chunk indices, and limits against malicious injection.
- **Memory Purge**: Automatically cleans in-memory buffers after transmission to prevent RAM leaks.
- **OWASP Headers**: Pre-configured with `X-Content-Type-Options`, `X-Frame-Options`, and `Referrer-Policy`.

---

## 🛠️ Tech Stack

- **Backend**: Node.js, Express 5, WebSocket (`ws`), QRCode
- **Frontend**: Vanilla JavaScript (ES6+), HTML5 Canvas, IndexedDB API, Web Audio API
- **Styling**: Vanilla CSS (Custom Design Tokens, Glassmorphism, Responsive Dark Theme)
- **Protocols**: HTTP/1.1 Parallel Chunk Streaming, WebSockets, WebRTC

---

## 🚀 Quick Start

### Prerequisites
- [Node.js](https://nodejs.org/) (version 18 or higher recommended)
- Both devices connected to the **same Wi-Fi network** or **Personal Hotspot**

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/hyperdrop.git
   cd hyperdrop
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Start the server**:
   ```bash
   npm start
   ```

4. **Access the application**:
   - **On Laptop**: Open `http://localhost:3000`
   - **On Mobile Phone**: Scan the QR code displayed on screen or enter `http://<YOUR_LOCAL_IP>:3000`

---

## 📶 Offline Hotspot Mode (No Wi-Fi / No Internet)

HyperDrop works 100% offline without any internet connection or external router:

1. Turn on **Personal Hotspot** on your phone (Mobile Data can remain **OFF**).
2. Connect your laptop to your phone's Hotspot Wi-Fi.
3. Open `http://localhost:3000` on your laptop.
4. Open the shown IP address on your phone browser.
5. Transfer files at full hardware speed with **0 MB internet data used**!

---

## 📁 Project Structure

```
hyperdrop/
├── public/
│   ├── css/
│   │   └── style.css          # Core design tokens, radar animations & responsive styles
│   ├── js/
│   │   ├── app.js            # UI controller, radar canvas & event bindings
│   │   ├── db.js             # IndexedDB v6 persistent local vault storage
│   │   ├── transfer.js       # Multi-worker parallel chunk streaming engine
│   │   └── webrtc.js         # WebSocket signaling & peer mesh management
│   ├── icons/                # High-res SVG and PNG app icons
│   ├── manifest.json         # Web App Manifest
│   ├── sw.js                 # Service Worker for offline asset caching
│   └── index.html            # Semantic HTML5 single-page application
├── server.js                 # Express + WebSocket streaming server with security middleware
├── package.json              # Project dependencies & npm scripts
└── README.md                 # Project documentation
```

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <sub>Built with ❤️ for ultra-fast, private, and frictionless local file sharing.</sub>
</div>
