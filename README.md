# HyperDrop ⚡ - Hybrid Local LAN & Remote WebRTC P2P File Transfer

**HyperDrop** is a high-speed, cross-platform file transfer engine engineered for instant local Wi-Fi radio streaming (100% offline) and remote WebRTC P2P file transfer across different networks (e.g. Laptop on Home Wi-Fi ↔ Phone on 4G/5G mobile data).

---

## 🌟 Key Features

1. **Hybrid Architecture (Local LAN + Remote WebRTC)**:
   - **Local Mode**: 100% offline Wi-Fi & Hotspot chunk streaming (4MB chunks, 50-100+ MB/s, 0 internet required).
   - **Remote Mode**: Cross-network WebRTC DataChannel streaming with STUN NAT traversal and TURN fallback.
2. **6-Digit Room Codes (`HD-XXXX`) & QR Pairing**:
   - Pair devices remotely by scanning a dynamic QR code or typing a simple 6-character room code.
3. **Automated Search & Peer Radar**:
   - UDP broadcast & discovery engine searches and discovers nearby laptops and phones automatically.
   - Interactive radar UI with live blips and `[Remote P2P]` badges.
4. **High-Speed Chunk Streaming Engine**:
   - 64KB pipelining with continuous `bufferedAmount` backpressure control.
   - Real-time speedometer gauge (MB/s), ETA calculations, and pause/resume/cancel controls.
5. **Data Vault & In-App Previews**:
   - Files land safely inside the isolated App Vault with SHA-256 integrity validation.
   - In-app media player and document previews for Videos, Audio, Images, and PDFs.
6. **Receiver Transfer Authorization**:
   - Security prompts asking receiver to Accept or Reject incoming transfer requests.
7. **Free Built-in Public Tunnel Support**:
   - Automatic public HTTPS tunnel generation for 4G/5G mobile device pairing from anywhere in the world.

---

## 🚀 How to Run

### Method 1: Double-Click
Double-click `start.bat` in the root folder.

### Method 2: Terminal
```bash
npm start
```

Open your browser at:
- **Local (Laptop):** `http://localhost:3000`
- **Mobile on Same Wi-Fi / Hotspot:** `http://<your-ip>:3000` (or scan Local QR Code)
- **Remote on 4G/5G Cellular Data:** Click **`[ 🌐 Remote Connect ]`** and scan Remote QR Code.

---

## 🧪 Automated Testing

Run the integration test suite:
```bash
npm test
```
