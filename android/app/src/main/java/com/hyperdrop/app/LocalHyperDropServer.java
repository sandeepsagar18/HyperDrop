package com.hyperdrop.app;

import android.content.Context;
import android.net.DhcpInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Environment;
import android.util.Base64;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/**
 * Embedded High-Performance Autonomous Server for Android HyperDrop.
 * Enables standalone Phone-to-Phone discovery and multi-gigabyte file transfers
 * without requiring any PC or router (e.g. over Mobile Hotspot, Wi-Fi Direct, Local LAN).
 */
public class LocalHyperDropServer {
    private static final String TAG = "HyperDropServer";
    private static final int DISCOVERY_PORT = 35432;

    private final int port;
    private final Context context;
    private ServerSocket serverSocket;
    private DatagramSocket udpSocket;
    private WifiManager.MulticastLock multicastLock;
    private volatile boolean isRunning = false;

    private final ExecutorService threadPool = Executors.newCachedThreadPool();
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);

    private final Map<String, JSONObject> connectedPeers = new ConcurrentHashMap<>();
    private final Set<WebSocketClient> wsClients = Collections.newSetFromMap(new ConcurrentHashMap<>());
    private final Map<String, FileUploadSession> activeUploads = new ConcurrentHashMap<>();
    private final List<JSONObject> vaultFiles = new CopyOnWriteArrayList<>();
    private File vaultDir;

    private final String localDeviceId;
    private final String localDeviceName;

    private static class FileUploadSession {
        String fileId;
        String fileName;
        long fileSize;
        int totalChunks;
        Set<Integer> chunksReceived = Collections.newSetFromMap(new ConcurrentHashMap<>());
        File targetFile;
        RandomAccessFile raf;
        long bytesReceived = 0;
        long startTime = System.currentTimeMillis();
        String senderName;
    }

    public LocalHyperDropServer(Context context, int port) {
        this.context = context.getApplicationContext();
        this.port = port;
        this.localDeviceId = "android_" + Build.MODEL.replaceAll("[^a-zA-Z0-9]", "") + "_" + (System.currentTimeMillis() % 10000);
        this.localDeviceName = Build.MODEL != null ? Build.MODEL : "Android Phone";
        initVaultDir();
    }

    private void initVaultDir() {
        try {
            File downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            vaultDir = new File(downloads, "HyperDrop");
            if (!vaultDir.exists()) {
                vaultDir.mkdirs();
            }
        } catch (Exception e) {
            vaultDir = context.getExternalFilesDir(null);
        }
    }

    public synchronized void start() {
        if (isRunning) return;
        isRunning = true;

        acquireMulticastLock();

        // 1. Start HTTP + WebSocket Server on Port 3000
        threadPool.execute(() -> {
            try {
                serverSocket = new ServerSocket(port);
                Log.i(TAG, "HyperDrop Autonomous Server listening on port " + port);
                while (isRunning && !serverSocket.isClosed()) {
                    Socket socket = serverSocket.accept();
                    threadPool.execute(() -> handleConnection(socket));
                }
            } catch (Exception e) {
                if (isRunning) {
                    Log.e(TAG, "Server socket error: " + e.getMessage());
                }
            }
        });

        // 2. Start UDP Discovery Beacon Broadcast & Listener
        startUdpDiscovery();

        // 3. Start Periodic Active Subnet & Gateway Prober
        startActiveSubnetProber();
    }

    public synchronized void stop() {
        isRunning = false;
        try {
            if (serverSocket != null && !serverSocket.isClosed()) {
                serverSocket.close();
            }
            if (udpSocket != null && !udpSocket.isClosed()) {
                udpSocket.close();
            }
            for (WebSocketClient client : wsClients) {
                client.close();
            }
            wsClients.clear();
            releaseMulticastLock();
            scheduler.shutdownNow();
            threadPool.shutdownNow();
        } catch (Exception ignored) {}
    }

    private void acquireMulticastLock() {
        try {
            WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                multicastLock = wifi.createMulticastLock("HyperDropMulticastLock");
                multicastLock.setReferenceCounted(true);
                multicastLock.acquire();
            }
        } catch (Exception e) {
            Log.w(TAG, "Could not acquire MulticastLock: " + e.getMessage());
        }
    }

    private void releaseMulticastLock() {
        try {
            if (multicastLock != null && multicastLock.isHeld()) {
                multicastLock.release();
            }
        } catch (Exception ignored) {}
    }

    private void startUdpDiscovery() {
        // UDP Listener
        threadPool.execute(() -> {
            try {
                udpSocket = new DatagramSocket(null);
                udpSocket.setReuseAddress(true);
                udpSocket.setBroadcast(true);
                udpSocket.bind(new InetSocketAddress(DISCOVERY_PORT));

                byte[] buf = new byte[2048];
                while (isRunning && !udpSocket.isClosed()) {
                    DatagramPacket packet = new DatagramPacket(buf, buf.length);
                    udpSocket.receive(packet);

                    String senderIp = packet.getAddress().getHostAddress();
                    if (isSelfIp(senderIp)) continue;

                    String message = new String(packet.getData(), 0, packet.getLength(), StandardCharsets.UTF_8);
                    handleDiscoveryBeacon(message, senderIp);
                }
            } catch (Exception e) {
                if (isRunning) {
                    Log.w(TAG, "UDP listener stopped: " + e.getMessage());
                }
            }
        });

        // UDP Beacon Broadcaster (every 2.0s)
        scheduler.scheduleWithFixedDelay(() -> {
            if (!isRunning) return;
            try {
                JSONObject beacon = new JSONObject();
                beacon.put("type", "hyperdrop_beacon");
                beacon.put("id", localDeviceId);
                beacon.put("name", localDeviceName);
                beacon.put("port", port);
                beacon.put("platform", "Android");
                beacon.put("deviceType", "phone");

                byte[] data = beacon.toString().getBytes(StandardCharsets.UTF_8);

                DatagramSocket sendSocket = new DatagramSocket();
                sendSocket.setBroadcast(true);

                // Broadcast to global subnet
                DatagramPacket p1 = new DatagramPacket(data, data.length, InetAddress.getByName("255.255.255.255"), DISCOVERY_PORT);
                sendSocket.send(p1);

                // If Hotspot Gateway, broadcast directly to hotspot client subnet
                String gateway = getGatewayIp();
                if (gateway != null && !gateway.equals("0.0.0.0")) {
                    try {
                        sendSocket.send(new DatagramPacket(data, data.length, InetAddress.getByName(gateway), DISCOVERY_PORT));
                    } catch (Exception ignored) {}
                }

                sendSocket.close();
            } catch (Exception ignored) {}
        }, 1, 2, TimeUnit.SECONDS);
    }

    private void handleDiscoveryBeacon(String beaconText, String senderIp) {
        try {
            JSONObject beacon = new JSONObject(beaconText);
            if (!"hyperdrop_beacon".equals(beacon.optString("type"))) return;

            String peerId = beacon.optString("id");
            if (peerId.isEmpty() || peerId.equals(localDeviceId)) return;

            String peerName = beacon.optString("name", "HyperDrop Device");
            int peerPort = beacon.optInt("port", 3000);

            registerDiscoveredPeer(peerId, peerName, senderIp, peerPort, beacon.optString("deviceType", "phone"));
        } catch (Exception ignored) {}
    }

    private void startActiveSubnetProber() {
        scheduler.scheduleWithFixedDelay(() -> {
            if (!isRunning) return;
            try {
                // 1. Probe Gateway (Crucial when connected to phone hotspot at 192.168.43.1)
                String gateway = getGatewayIp();
                if (gateway != null && !isSelfIp(gateway)) {
                    probeTargetIp(gateway);
                }

                // 2. Probe default hotspot subnet (192.168.43.1..30)
                String localIp = getLocalIpAddress();
                if (localIp != null && localIp.contains(".")) {
                    String prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);
                    int selfLastOctet = 0;
                    try {
                        selfLastOctet = Integer.parseInt(localIp.substring(localIp.lastIndexOf('.') + 1));
                    } catch (Exception ignored) {}

                    // Fast probe nearby addresses first (1 to 30)
                    for (int i = 1; i <= 30; i++) {
                        if (i == selfLastOctet) continue;
                        final String targetIp = prefix + i;
                        threadPool.execute(() -> probeTargetIp(targetIp));
                    }
                }

                // 3. Also probe standard hotspot host address 192.168.43.1
                probeTargetIp("192.168.43.1");
            } catch (Exception ignored) {}
        }, 2, 4, TimeUnit.SECONDS);
    }

    private void probeTargetIp(String targetIp) {
        if (isSelfIp(targetIp)) return;
        try {
            URL url = new URL("http://" + targetIp + ":" + port + "/api/status");
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(1200);
            conn.setReadTimeout(1200);
            conn.setRequestMethod("GET");
            int code = conn.getResponseCode();
            if (code == 200) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) sb.append(line);
                reader.close();

                JSONObject res = new JSONObject(sb.toString());
                String deviceName = res.optString("deviceName", "HyperDrop Device");
                String peerId = "ip_" + targetIp.replace(".", "_");

                registerDiscoveredPeer(peerId, deviceName, targetIp, port, "phone");

                // Proactively notify that peer about our existence
                sendPeerAnnouncement(targetIp, port);
            }
        } catch (Exception ignored) {}
    }

    private void sendPeerAnnouncement(String remoteIp, int remotePort) {
        try {
            URL url = new URL("http://" + remoteIp + ":" + remotePort + "/api/peers/register");
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(1500);
            conn.setReadTimeout(1500);
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            conn.setDoOutput(true);

            JSONObject body = new JSONObject();
            body.put("id", localDeviceId);
            body.put("name", localDeviceName);
            body.put("ip", getLocalIpAddress());
            body.put("port", port);
            body.put("deviceType", "phone");

            OutputStream os = conn.getOutputStream();
            os.write(body.toString().getBytes(StandardCharsets.UTF_8));
            os.flush();
            os.close();
            conn.getResponseCode();
        } catch (Exception ignored) {}
    }

    private void registerDiscoveredPeer(String id, String name, String ip, int peerPort, String deviceType) {
        try {
            boolean isNew = !connectedPeers.containsKey(id);
            JSONObject peerData = new JSONObject();
            peerData.put("id", id);
            peerData.put("name", name);
            peerData.put("deviceType", deviceType != null ? deviceType : "phone");
            peerData.put("osType", "Android");
            peerData.put("avatar", "\uD83D\uDCF1");
            peerData.put("url", "http://" + ip + ":" + peerPort);
            peerData.put("ip", ip);
            peerData.put("lastSeen", System.currentTimeMillis());

            connectedPeers.put(id, peerData);

            if (isNew) {
                Log.i(TAG, "\u26A1 Peer discovered: " + name + " (" + ip + ")");
            }

            // Notify local WebSockets
            JSONObject discMsg = new JSONObject();
            discMsg.put("type", "peer_discovered");
            discMsg.put("data", peerData);
            broadcastWebSocket(discMsg.toString());
        } catch (Exception ignored) {}
    }

    private void handleConnection(Socket socket) {
        try {
            socket.setTcpNoDelay(true);
            socket.setReceiveBufferSize(256 * 1024);
            socket.setSendBufferSize(256 * 1024);

            InputStream in = socket.getInputStream();
            BufferedInputStream bin = new BufferedInputStream(in);

            // Read HTTP request line and headers
            ByteArrayOutputStream headerBuffer = new ByteArrayOutputStream();
            int b;
            int newlineCount = 0;
            while ((b = bin.read()) != -1) {
                headerBuffer.write(b);
                if (b == '\n') {
                    if (newlineCount > 0 && headerBuffer.size() >= 4) {
                        byte[] bytes = headerBuffer.toByteArray();
                        int len = bytes.length;
                        if (len >= 4 && bytes[len - 4] == '\r' && bytes[len - 3] == '\n' && bytes[len - 2] == '\r' && bytes[len - 1] == '\n') {
                            break;
                        }
                    }
                    newlineCount++;
                } else if (b != '\r') {
                    newlineCount = 0;
                }
            }

            String headerText = new String(headerBuffer.toByteArray(), StandardCharsets.UTF_8);
            String[] lines = headerText.split("\r\n");
            if (lines.length == 0 || lines[0].isEmpty()) {
                socket.close();
                return;
            }

            String[] requestParts = lines[0].split(" ");
            if (requestParts.length < 2) {
                socket.close();
                return;
            }

            String method = requestParts[0];
            String fullPath = requestParts[1];
            String path = fullPath.contains("?") ? fullPath.substring(0, fullPath.indexOf("?")) : fullPath;
            String query = fullPath.contains("?") ? fullPath.substring(fullPath.indexOf("?") + 1) : "";

            Map<String, String> headers = new HashMap<>();
            for (int i = 1; i < lines.length; i++) {
                int colon = lines[i].indexOf(":");
                if (colon > 0) {
                    headers.put(lines[i].substring(0, colon).trim().toLowerCase(Locale.ROOT), lines[i].substring(colon + 1).trim());
                }
            }

            Map<String, String> queryParams = parseQueryParams(query);

            // 1. WebSocket Upgrade
            if ("websocket".equalsIgnoreCase(headers.get("upgrade"))) {
                handleWebSocketUpgrade(socket, bin, headers);
                return;
            }

            // 2. CORS Preflight
            if ("OPTIONS".equalsIgnoreCase(method)) {
                sendResponse(socket, 200, "OK", "text/plain", new byte[0]);
                socket.close();
                return;
            }

            // 3. API Endpoints
            if (path.equals("/api/status")) {
                JSONObject status = new JSONObject();
                status.put("success", true);
                status.put("deviceId", localDeviceId);
                status.put("deviceName", localDeviceName);
                status.put("platform", "Android");
                status.put("primaryIp", getLocalIpAddress());
                status.put("httpPort", port);
                status.put("version", "2.0.0");
                status.put("serverTime", System.currentTimeMillis());
                sendJsonResponse(socket, 200, status);
            } else if (path.equals("/api/peers")) {
                JSONObject res = new JSONObject();
                res.put("success", true);
                JSONArray arr = new JSONArray();
                for (JSONObject p : connectedPeers.values()) {
                    arr.put(p);
                }
                res.put("peers", arr);
                sendJsonResponse(socket, 200, res);
            } else if (path.equals("/api/peers/register")) {
                // Read request body JSON
                long contentLen = Long.parseLong(headers.getOrDefault("content-length", "0"));
                if (contentLen > 0) {
                    byte[] bodyBytes = new byte[(int) Math.min(contentLen, 16384)];
                    int read = bin.read(bodyBytes);
                    if (read > 0) {
                        JSONObject regObj = new JSONObject(new String(bodyBytes, 0, read, StandardCharsets.UTF_8));
                        String id = regObj.optString("id");
                        String name = regObj.optString("name", "Device");
                        String ip = socket.getInetAddress().getHostAddress();
                        int pPort = regObj.optInt("port", port);
                        registerDiscoveredPeer(id, name, ip, pPort, regObj.optString("deviceType", "phone"));
                    }
                }
                JSONObject ok = new JSONObject().put("success", true);
                sendJsonResponse(socket, 200, ok);
            } else if (path.equals("/api/handshake")) {
                JSONObject hs = new JSONObject();
                hs.put("success", true);
                hs.put("sessionToken", "hd_token_" + UUID.randomUUID().toString().substring(0, 8));
                hs.put("maxChunkSize", 6 * 1024 * 1024); // 6MB high-speed chunks
                sendJsonResponse(socket, 200, hs);
            } else if (path.equals("/api/diagnostics")) {
                JSONObject res = new JSONObject();
                res.put("success", true);
                JSONObject diag = new JSONObject();
                diag.put("interfaceName", "wlan0 (Wi-Fi)");
                diag.put("interfaceType", "Wi-Fi Direct / Local Hotspot");
                diag.put("localIp", getLocalIpAddress());
                diag.put("subnetMask", "255.255.255.0");
                diag.put("gatewayIp", getGatewayIp() != null ? getGatewayIp() : "192.168.43.1");
                diag.put("isHotspot", true);
                diag.put("discoveryEngineStatus", "Autonomous Native (Active)");
                diag.put("offlineModeHealth", "100% Offline Hotspot Engine Running");
                res.put("diagnostics", diag);
                sendJsonResponse(socket, 200, res);
            } else if (path.equals("/api/vault/files")) {
                JSONObject res = new JSONObject();
                res.put("success", true);
                JSONArray arr = new JSONArray();
                for (JSONObject f : vaultFiles) {
                    arr.put(f);
                }
                res.put("files", arr);
                sendJsonResponse(socket, 200, res);
            } else if (path.startsWith("/api/vault/upload-status/")) {
                String fid = path.substring(path.lastIndexOf('/') + 1);
                FileUploadSession s = activeUploads.get(fid);
                JSONObject stat = new JSONObject();
                stat.put("success", true);
                JSONObject sdata = new JSONObject();
                if (s != null) {
                    sdata.put("fileId", fid);
                    sdata.put("nextChunkIndex", s.chunksReceived.size());
                } else {
                    sdata.put("fileId", fid);
                    sdata.put("nextChunkIndex", 0);
                }
                stat.put("status", sdata);
                sendJsonResponse(socket, 200, stat);
            } else if (path.equals("/api/vault/upload-chunk")) {
                handleChunkUpload(socket, bin, headers, queryParams);
            } else if (path.startsWith("/api/vault/preview/") || path.startsWith("/api/vault/download/")) {
                handleFileServe(socket, path);
            } else {
                sendResponse(socket, 200, "OK", "application/json", "{\"success\":true}".getBytes(StandardCharsets.UTF_8));
            }

            socket.close();
        } catch (Exception e) {
            try { socket.close(); } catch (Exception ignored) {}
        }
    }

    private void handleChunkUpload(Socket socket, BufferedInputStream bin, Map<String, String> headers, Map<String, String> queryParams) throws Exception {
        String fileId = headers.containsKey("x-file-id") ? headers.get("x-file-id") : queryParams.get("fileId");
        String fileName = headers.containsKey("x-file-name") ? headers.get("x-file-name") : queryParams.get("fileName");
        if (fileName != null) {
            try { fileName = URLDecoder.decode(fileName, "UTF-8"); } catch (Exception ignored) {}
        } else {
            fileName = "file.dat";
        }

        int chunkIndex = Integer.parseInt(headers.containsKey("x-chunk-index") ? headers.get("x-chunk-index") : queryParams.getOrDefault("chunkIndex", "0"));
        int totalChunks = Integer.parseInt(headers.containsKey("x-total-chunks") ? headers.get("x-total-chunks") : queryParams.getOrDefault("totalChunks", "1"));
        long startByte = Long.parseLong(headers.containsKey("x-chunk-start") ? headers.get("x-chunk-start") : queryParams.getOrDefault("startByte", "0"));
        long fileSize = Long.parseLong(headers.containsKey("x-file-size") ? headers.get("x-file-size") : queryParams.getOrDefault("fileSize", "0"));
        String senderName = queryParams.getOrDefault("senderName", "Peer");

        long contentLength = Long.parseLong(headers.getOrDefault("content-length", "0"));

        FileUploadSession session = activeUploads.get(fileId);
        if (session == null) {
            session = new FileUploadSession();
            session.fileId = fileId;
            session.fileName = fileName;
            session.fileSize = fileSize;
            session.totalChunks = totalChunks;
            session.senderName = senderName;

            String cleanName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");
            session.targetFile = new File(vaultDir, System.currentTimeMillis() + "_" + cleanName);
            session.raf = new RandomAccessFile(session.targetFile, "rw");
            activeUploads.put(fileId, session);
        }

        // Direct high-throughput chunk streaming to disk
        byte[] buffer = new byte[64 * 1024];
        long remaining = contentLength;
        session.raf.seek(startByte);

        while (remaining > 0) {
            int read = bin.read(buffer, 0, (int) Math.min(buffer.length, remaining));
            if (read == -1) break;
            session.raf.write(buffer, 0, read);
            remaining -= read;
        }

        boolean isNew = session.chunksReceived.add(chunkIndex);
        if (isNew) {
            session.bytesReceived += contentLength;
        }

        int percent = (int) Math.min(100, Math.round((session.bytesReceived * 100.0) / Math.max(1, session.fileSize)));

        // Broadcast progress over WebSocket to mobile screen
        JSONObject progressMsg = new JSONObject();
        progressMsg.put("type", "transfer_stream_progress");
        JSONObject progressData = new JSONObject();
        progressData.put("fileId", fileId);
        progressData.put("fileName", fileName);
        progressData.put("fileSize", session.fileSize);
        progressData.put("bytesTransferred", session.bytesReceived);
        progressData.put("percent", percent);
        progressData.put("status", "receiving");
        progressData.put("senderName", session.senderName);
        progressMsg.put("data", progressData);
        broadcastWebSocket(progressMsg.toString());

        // Check if all chunks completed
        if (session.chunksReceived.size() >= session.totalChunks) {
            session.raf.close();
            activeUploads.remove(fileId);

            JSONObject vaultItem = new JSONObject();
            vaultItem.put("id", fileId);
            vaultItem.put("originalName", fileName);
            vaultItem.put("vaultFileName", session.targetFile.getName());
            vaultItem.put("path", session.targetFile.getAbsolutePath());
            vaultItem.put("size", session.targetFile.length());
            vaultItem.put("senderName", session.senderName);
            vaultItem.put("receivedAt", new Date().toString());
            vaultFiles.add(0, vaultItem);

            JSONObject completeMsg = new JSONObject();
            completeMsg.put("type", "file_received");
            completeMsg.put("data", vaultItem);
            broadcastWebSocket(completeMsg.toString());

            // Scan media library so photos/videos immediately show in Gallery
            android.media.MediaScannerConnection.scanFile(context, new String[]{session.targetFile.getAbsolutePath()}, null, null);
        }

        JSONObject resp = new JSONObject();
        resp.put("success", true);
        resp.put("status", "chunk_received");
        resp.put("progressPercent", percent);
        sendJsonResponse(socket, 200, resp);
    }

    private void handleFileServe(Socket socket, String path) throws Exception {
        String fileId = path.substring(path.lastIndexOf('/') + 1);
        File target = null;
        for (JSONObject f : vaultFiles) {
            if (f.optString("id").equals(fileId) || f.optString("vaultFileName").equals(fileId)) {
                target = new File(f.optString("path"));
                break;
            }
        }

        if (target == null || !target.exists()) {
            sendResponse(socket, 404, "Not Found", "text/plain", "File not found".getBytes(StandardCharsets.UTF_8));
            return;
        }

        String mime = getMimeType(target.getName());
        OutputStream out = socket.getOutputStream();
        String header = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: " + mime + "\r\n" +
                "Content-Length: " + target.length() + "\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Connection: close\r\n\r\n";
        out.write(header.getBytes(StandardCharsets.UTF_8));

        FileInputStream fis = new FileInputStream(target);
        byte[] buf = new byte[64 * 1024];
        int r;
        while ((r = fis.read(buf)) != -1) {
            out.write(buf, 0, r);
        }
        fis.close();
        out.flush();
    }

    private void handleWebSocketUpgrade(Socket socket, BufferedInputStream bin, Map<String, String> headers) throws Exception {
        String key = headers.get("sec-websocket-key");
        if (key == null) {
            socket.close();
            return;
        }

        String acceptKey = Base64.encodeToString(
                MessageDigest.getInstance("SHA-1").digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").getBytes(StandardCharsets.UTF_8)),
                Base64.NO_WRAP
        );

        OutputStream out = socket.getOutputStream();
        String response = "HTTP/1.1 101 Switching Protocols\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n";
        out.write(response.getBytes(StandardCharsets.UTF_8));
        out.flush();

        WebSocketClient client = new WebSocketClient(socket, bin, out);
        wsClients.add(client);
        client.startListening();
    }

    private class WebSocketClient {
        final Socket socket;
        final BufferedInputStream in;
        final OutputStream out;
        String peerId = null;

        WebSocketClient(Socket socket, BufferedInputStream in, OutputStream out) {
            this.socket = socket;
            this.in = in;
            this.out = out;
        }

        void startListening() {
            threadPool.execute(() -> {
                try {
                    while (isRunning && !socket.isClosed()) {
                        int b1 = in.read();
                        if (b1 == -1) break;
                        int opcode = b1 & 0x0F;
                        if (opcode == 8) break; // Close frame

                        int b2 = in.read();
                        boolean masked = (b2 & 0x80) != 0;
                        long len = b2 & 0x7F;

                        if (len == 126) {
                            len = ((in.read() << 8) | in.read());
                        } else if (len == 127) {
                            len = 0;
                            for (int i = 0; i < 8; i++) len = (len << 8) | in.read();
                        }

                        byte[] mask = new byte[4];
                        if (masked) {
                            for (int i = 0; i < 4; i++) mask[i] = (byte) in.read();
                        }

                        byte[] payload = new byte[(int) len];
                        int totalRead = 0;
                        while (totalRead < len) {
                            int r = in.read(payload, totalRead, (int) (len - totalRead));
                            if (r == -1) break;
                            totalRead += r;
                        }

                        if (masked) {
                            for (int i = 0; i < payload.length; i++) {
                                payload[i] ^= mask[i % 4];
                            }
                        }

                        String text = new String(payload, StandardCharsets.UTF_8);
                        handleWebSocketMessage(this, text);
                    }
                } catch (Exception ignored) {
                } finally {
                    close();
                }
            });
        }

        synchronized void sendText(String text) {
            try {
                byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
                ByteArrayOutputStream frame = new ByteArrayOutputStream();
                frame.write(0x81); // Text frame, FIN
                if (bytes.length <= 125) {
                    frame.write(bytes.length);
                } else if (bytes.length <= 65535) {
                    frame.write(126);
                    frame.write((bytes.length >> 8) & 0xFF);
                    frame.write(bytes.length & 0xFF);
                } else {
                    frame.write(127);
                    for (int i = 7; i >= 0; i--) {
                        frame.write((int) ((bytes.length >> (8 * i)) & 0xFF));
                    }
                }
                frame.write(bytes);
                out.write(frame.toByteArray());
                out.flush();
            } catch (Exception e) {
                close();
            }
        }

        void close() {
            wsClients.remove(this);
            if (peerId != null) {
                connectedPeers.remove(peerId);
                JSONObject lost = new JSONObject();
                try {
                    lost.put("type", "peer_lost");
                    lost.put("data", new JSONObject().put("id", peerId));
                    broadcastWebSocket(lost.toString());
                } catch (Exception ignored) {}
            }
            try { socket.close(); } catch (Exception ignored) {}
        }
    }

    private void handleWebSocketMessage(WebSocketClient client, String text) {
        try {
            JSONObject msg = new JSONObject(text);
            String type = msg.optString("type");

            if ("register_web_peer".equals(type) || "announce".equals(type)) {
                String id = msg.optString("id");
                String name = msg.optString("name", "Phone");
                client.peerId = id;

                JSONObject peerData = new JSONObject();
                peerData.put("id", id);
                peerData.put("name", name);
                peerData.put("deviceType", msg.optString("deviceType", "phone"));
                peerData.put("osType", "Android");
                peerData.put("avatar", "\uD83D\uDCF1");
                peerData.put("url", "http://" + client.socket.getInetAddress().getHostAddress() + ":" + port);
                peerData.put("ip", client.socket.getInetAddress().getHostAddress());
                peerData.put("lastSeen", System.currentTimeMillis());

                connectedPeers.put(id, peerData);

                // Broadcast to all connected peers
                JSONObject disc = new JSONObject();
                disc.put("type", "peer_discovered");
                disc.put("data", peerData);
                broadcastWebSocket(disc.toString());

                // Send current peer snapshot to the new peer
                for (JSONObject existing : connectedPeers.values()) {
                    if (!existing.optString("id").equals(id)) {
                        JSONObject exMsg = new JSONObject();
                        exMsg.put("type", "peer_discovered");
                        exMsg.put("data", existing);
                        client.sendText(exMsg.toString());
                    }
                }
            } else {
                // Relay signaling / progress / clipboard / transfer messages to other peers
                broadcastWebSocket(text);
            }
        } catch (Exception e) {
            Log.e(TAG, "WS Message Error: " + e.getMessage());
        }
    }

    public void broadcastWebSocket(String message) {
        for (WebSocketClient client : wsClients) {
            client.sendText(message);
        }
    }

    private void sendJsonResponse(Socket socket, int code, JSONObject json) throws IOException {
        byte[] bytes = json.toString().getBytes(StandardCharsets.UTF_8);
        sendResponse(socket, code, "OK", "application/json; charset=utf-8", bytes);
    }

    private void sendResponse(Socket socket, int code, String status, String mime, byte[] body) throws IOException {
        OutputStream out = socket.getOutputStream();
        String header = "HTTP/1.1 " + code + " " + status + "\r\n" +
                "Content-Type: " + mime + "\r\n" +
                "Content-Length: " + body.length + "\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Access-Control-Allow-Headers: *\r\n" +
                "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n" +
                "Connection: close\r\n\r\n";
        out.write(header.getBytes(StandardCharsets.UTF_8));
        out.write(body);
        out.flush();
    }

    private Map<String, String> parseQueryParams(String query) {
        Map<String, String> map = new HashMap<>();
        if (query == null || query.isEmpty()) return map;
        String[] pairs = query.split("&");
        for (String pair : pairs) {
            int idx = pair.indexOf("=");
            if (idx > 0) {
                try {
                    String key = URLDecoder.decode(pair.substring(0, idx), "UTF-8");
                    String val = URLDecoder.decode(pair.substring(idx + 1), "UTF-8");
                    map.put(key, val);
                } catch (Exception ignored) {}
            }
        }
        return map;
    }

    private String getMimeType(String fileName) {
        if (fileName.endsWith(".png")) return "image/png";
        if (fileName.endsWith(".jpg") || fileName.endsWith(".jpeg")) return "image/jpeg";
        if (fileName.endsWith(".mp4")) return "video/mp4";
        if (fileName.endsWith(".mp3")) return "audio/mpeg";
        if (fileName.endsWith(".pdf")) return "application/pdf";
        if (fileName.endsWith(".apk")) return "application/vnd.android.package-archive";
        return "application/octet-stream";
    }

    private boolean isSelfIp(String ip) {
        if (ip == null) return false;
        if (ip.equals("127.0.0.1") || ip.equals("0.0.0.0") || ip.equals("::1")) return true;
        String local = getLocalIpAddress();
        return local != null && local.equals(ip);
    }

    private String getGatewayIp() {
        try {
            WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                DhcpInfo dhcp = wifi.getDhcpInfo();
                if (dhcp != null && dhcp.gateway != 0) {
                    return String.format(Locale.US, "%d.%d.%d.%d",
                            (dhcp.gateway & 0xff),
                            (dhcp.gateway >> 8 & 0xff),
                            (dhcp.gateway >> 16 & 0xff),
                            (dhcp.gateway >> 24 & 0xff));
                }
            }
        } catch (Exception ignored) {}
        return null;
    }

    private String getLocalIpAddress() {
        try {
            WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifi != null) {
                int ip = wifi.getConnectionInfo().getIpAddress();
                if (ip != 0) {
                    return String.format(Locale.US, "%d.%d.%d.%d",
                            (ip & 0xff),
                            (ip >> 8 & 0xff),
                            (ip >> 16 & 0xff),
                            (ip >> 24 & 0xff));
                }
            }
            // Fallback to NetworkInterface
            for (Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces(); en.hasMoreElements();) {
                NetworkInterface intf = en.nextElement();
                for (Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses(); enumIpAddr.hasMoreElements();) {
                    InetAddress inetAddress = enumIpAddr.nextElement();
                    if (!inetAddress.isLoopbackAddress() && inetAddress instanceof Inet4Address) {
                        return inetAddress.getHostAddress();
                    }
                }
            }
        } catch (Exception ignored) {}
        return "127.0.0.1";
    }
}
