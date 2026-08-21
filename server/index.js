const http = require('http');
const path = require('path');
const express = require('express');
const cors = require('cors');
const { WebSocketServer } = require('ws');

const DiscoveryEngine = require('./network/discovery');
const networkMonitor = require('./network/networkMonitor');
const { TransferWorkerPool } = require('./transfer/workerPool');
const vaultManager = require('./vault/vaultManager');
const createApiRouter = require('./routes/api');
const { getPrimaryIp } = require('./network/interfaces');
const { handleSignalingMessage, handleSignalingDisconnect } = require('./signaling/signalingServer');
const { getIceConfiguration } = require('./network/iceConfig');

const PORT = process.env.PORT || 3000;

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Start Live Network Monitor
networkMonitor.start();

// Middlewares
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Captive Portal & Android/iOS Offline Hotspot Keep-Alive Endpoints
app.get(['/generate_204', '/gen_204', '/mobile/status.php'], (req, res) => {
    res.status(204).end();
});

app.get(['/hotspot-detect.html', '/canonical.html', '/success.html'], (req, res) => {
    res.status(200).send('<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>');
});

app.get(['/ncsi.txt', '/connecttest.txt', '/check_network_status.txt'], (req, res) => {
    res.status(200).send('Microsoft NCSI');
});

// Serve static frontend
app.use(express.static(path.join(__dirname, '..', 'client'), {
    setHeaders: (res, filePath) => {
        if (filePath.endsWith('.html') || filePath.endsWith('sw.js')) {
            res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        }
    }
}));

// Initialize Core Services
const discoveryEngine = new DiscoveryEngine({
    httpPort: PORT
});

// Wire Network Shift Handlers
networkMonitor.on('network_changed', (changeData) => {
    discoveryEngine.onNetworkChanged(changeData);
    broadcastWs('network_changed', changeData);
});

const workerPool = new TransferWorkerPool({
    maxConcurrentWorkers: 8
});

// Mount API routes
app.use('/api', createApiRouter({ discoveryEngine, workerPool }));

// Broadcast helper for WebSockets (with targeted recipient routing)
function broadcastWs(type, data, targetFilter = null) {
    const payload = JSON.stringify({ type, data, timestamp: Date.now() });
    for (const client of wss.clients) {
        if (client.readyState === 1) { // OPEN
            if (targetFilter && typeof targetFilter === 'function') {
                if (!targetFilter(client)) continue;
            }
            client.send(payload);
        }
    }
}

// Wire Event Handlers to WebSocket real-time broadcast
discoveryEngine.on('peer_discovered', (peer) => broadcastWs('peer_discovered', peer));
discoveryEngine.on('peer_lost', (peer) => broadcastWs('peer_lost', peer));
discoveryEngine.on('peer_updated', (peer) => broadcastWs('peer_updated', peer));
discoveryEngine.on('device_renamed', (data) => broadcastWs('device_renamed', data));
discoveryEngine.on('clipboard_synced', (item) => {
    broadcastWs('clipboard_synced', item, (client) => {
        if (!item.targetPeerIds || item.targetPeerIds.includes('all')) return true;
        return item.targetPeerIds.includes(client.peerId) || client.peerId === item.senderId;
    });
});

workerPool.on('worker_progress', (info) => broadcastWs('worker_progress', info));
workerPool.on('worker_status', (info) => broadcastWs('worker_status', info));
workerPool.on('worker_error', (err) => broadcastWs('worker_error', err));

// TARGETED TRANSFER ROUTING: Send only to sender & chosen target recipient
vaultManager.on('upload_progress', (info) => {
    broadcastWs('incoming_transfer_progress', info, (client) => {
        if (!info.targetPeerId || info.targetPeerId === 'all') return true;
        return client.peerId === info.targetPeerId || client.peerId === info.senderId;
    });
});

vaultManager.on('upload_cancelled', (info) => broadcastWs('transfer_cancelled', info));

vaultManager.on('file_received', (item) => {
    broadcastWs('file_received', item, (client) => {
        if (!item.targetPeerId || item.targetPeerId === 'all') return true;
        return client.peerId === item.targetPeerId || client.peerId === item.senderId;
    });
});

vaultManager.on('file_deleted', (id) => broadcastWs('file_deleted', { id }));
vaultManager.on('vault_cleared', () => broadcastWs('vault_cleared', {}));

wss.on('connection', (ws, req) => {
    // Extract client IP address
    let clientIp = req.socket.remoteAddress || '127.0.0.1';
    if (clientIp.startsWith('::ffff:')) {
        clientIp = clientIp.replace('::ffff:', '');
    }

    let registeredPeerId = null;

    // Send initial snapshot on client connect
    ws.send(JSON.stringify({
        type: 'init_state',
        data: {
            peers: discoveryEngine.getPeers(),
            workers: workerPool.getAllWorkers(),
            vaultStats: vaultManager.getVaultStats(),
            primaryIp: getPrimaryIp(),
            port: PORT,
            yourIp: clientIp
        }
    }));

    // Handle messages from web clients (peer registration + WebRTC signaling)
    ws.on('message', (message) => {
        try {
            const parsed = JSON.parse(message.toString());

            // 1. WebRTC Signaling Dispatch
            handleSignalingMessage(ws, parsed, wss);

            // 2. Local Discovery & Heartbeat
            if (parsed.type === 'register_web_peer') {
                registeredPeerId = parsed.id;
                ws.peerId = parsed.id; // Attach peerId to socket for targeted routing!
                const peer = discoveryEngine.registerWebClient({
                    id: parsed.id,
                    name: parsed.name,
                    deviceType: parsed.deviceType,
                    osType: parsed.osType,
                    avatar: parsed.avatar,
                    ip: clientIp,
                    httpPort: PORT
                });
                // Acknowledge registration
                ws.send(JSON.stringify({ type: 'registered_ack', data: peer }));
            } else if (parsed.type === 'heartbeat') {
                const peer = discoveryEngine.peers.get(parsed.id);
                if (peer) {
                    peer.lastSeen = Date.now();
                }
            }
        } catch (err) {
            console.error('[WS] Message error:', err.message);
        }
    });

    // Instant Peer Removal upon Disconnect
    ws.on('close', () => {
        handleSignalingDisconnect(ws);
        if (registeredPeerId) {
            const lostPeer = discoveryEngine.peers.get(registeredPeerId);
            discoveryEngine.peers.delete(registeredPeerId);
            if (lostPeer) {
                discoveryEngine.emit('peer_lost', lostPeer);
                broadcastWs('peer_lost', lostPeer);
            }
        }
    });
});

// Start Server (only when not running in Vercel Serverless environment)
if (!process.env.VERCEL) {
    server.listen(PORT, '0.0.0.0', () => {
        const ip = getPrimaryIp();
        console.log(`=======================================================`);
        console.log(`⚡ HyperDrop Server running at: http://${ip}:${PORT}`);
        console.log(`⚡ Local Access: http://localhost:${PORT}`);
        console.log(`⚡ UDP Peer Discovery Engine running on port 35432`);
        console.log(`⚡ App Vault location: ${vaultManager.vaultDir}`);
        console.log(`=======================================================`);

        // Start UDP discovery beacon
        discoveryEngine.start();
    });
}

process.on('uncaughtException', (err) => {
    console.error('[HyperDrop Error Safe Guard]', err.message);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('[HyperDrop Rejection Safe Guard]', reason);
});

process.on('SIGINT', () => {
    console.log('\nStopping HyperDrop...');
    discoveryEngine.stop();
    server.close(() => {
        process.exit(0);
    });
});

module.exports = app;
