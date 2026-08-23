const express = require('express');
const multer = require('multer');
const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');
const { getNetworkInterfaces, getPrimaryIp } = require('../network/interfaces');
const networkMonitor = require('../network/networkMonitor');
const vaultManager = require('../vault/vaultManager');
const { exportFileToStorage, batchExportToStorage, getSystemDirectories } = require('../vault/exportHandler');
const crypto = require('crypto');

const os = require('os');
const activeSessions = new Map(); // token -> { deviceId, deviceName, createdAt }

const TEMP_UPLOADS_DIR = path.join(process.cwd(), '.hyperdrop_vault', 'temp_uploads');

function createApiRouter({ discoveryEngine, workerPool, appState, broadcastWs }) {
    const router = express.Router();

    // Ensure temp_uploads directory exists
    try {
        if (!fs.existsSync(TEMP_UPLOADS_DIR)) {
            fs.mkdirSync(TEMP_UPLOADS_DIR, { recursive: true });
        }
    } catch (e) {}

    // Storage for direct uploads from web browser
    const upload = multer({ dest: TEMP_UPLOADS_DIR });

    // 0. Handshake & Transfer Authorization Request
    router.post('/transfer/request', (req, res) => {
        const { fileId, fileName, fileSize, senderName, targetPeerIp } = req.body;
        if (discoveryEngine.emit) {
            discoveryEngine.emit('transfer_requested', {
                fileId: fileId || `f_${Date.now()}`,
                fileName: fileName || 'Unknown File',
                fileSize: fileSize || 0,
                senderName: senderName || 'Nearby Laptop',
                targetPeerIp
            });
        }
        res.json({ accepted: true, message: 'Transfer request prompted' });
    });

    router.post('/handshake', (req, res) => {
        const { deviceId, deviceName, protocolVersion, appType } = req.body;
        const callerId = deviceId || `client_${req.ip.replace(/[^a-zA-Z0-9]/g, '_')}`;
        const callerName = deviceName || 'Nearby Device';

        const sessionToken = `hd_sec_${crypto.randomBytes(16).toString('hex')}`;
        activeSessions.set(sessionToken, {
            deviceId: callerId,
            deviceName: callerName,
            createdAt: Date.now()
        });

        console.log(`=======================================================`);
        console.log(`[HANDSHAKE] Established connection with: ${callerName} (${callerId})`);
        console.log(`[HANDSHAKE] Session Token: ${sessionToken.substring(0, 14)}... | Protocol: v${protocolVersion || 1}`);
        console.log(`=======================================================`);

        res.json({
            accepted: true,
            deviceId: discoveryEngine.deviceId,
            deviceName: discoveryEngine.deviceName,
            port: discoveryEngine.httpPort,
            sessionToken,
            maxChunkSize: 4 * 1024 * 1024, // 4MB chunks
            protocolVersion: 1,
            serverIp: networkMonitor.currentIp
        });
    });

    // Network Diagnostics Endpoint
    router.get('/diagnostics', (req, res) => {
        const diag = networkMonitor.getDiagnostics();
        diag.discoveryEngineStatus = discoveryEngine.isRunning ? 'Active & Listening' : 'Inactive';
        diag.discoveredPeersCount = discoveryEngine.getPeers().length;
        diag.peers = discoveryEngine.getPeers();
        res.json({
            success: true,
            diagnostics: diag
        });
    });

    // Remote ICE & WebRTC Configuration
    router.get('/remote/ice-config', (req, res) => {
        const { getIceConfiguration } = require('../network/iceConfig');
        res.json({
            success: true,
            iceConfig: getIceConfiguration()
        });
    });

    // 1. System Status & Network
    router.get('/status', (req, res) => {
        const ifaces = getNetworkInterfaces();
        const primaryIp = getPrimaryIp();
        res.json({
            success: true,
            deviceId: discoveryEngine.deviceId,
            deviceName: discoveryEngine.deviceName,
            deviceType: discoveryEngine.deviceType,
            osType: discoveryEngine.osType,
            httpPort: discoveryEngine.httpPort,
            primaryIp,
            interfaces: ifaces,
            appUrl: `http://${primaryIp}:${discoveryEngine.httpPort}`
        });
    });

    // Resumable Upload Status Check
    router.get('/vault/upload-status/:fileId', (req, res) => {
        const status = vaultManager.getUploadStatus(req.params.fileId);
        res.json({ success: true, status });
    });

    // Rename Host Device
    router.post('/device/rename', (req, res) => {
        const { name } = req.body;
        if (!name || !name.trim()) {
            return res.status(400).json({ success: false, error: 'Device name cannot be empty' });
        }
        discoveryEngine.deviceName = name.trim();
        discoveryEngine._broadcastBeacon();
        if (discoveryEngine.emit) {
            discoveryEngine.emit('device_renamed', { deviceName: discoveryEngine.deviceName });
        }
        res.json({ success: true, deviceName: discoveryEngine.deviceName });
    });

    // 2. Discovered Peers
    router.get('/peers', (req, res) => {
        const clientIp = req.ip.replace('::ffff:', '');
        const isLocalhost = clientIp === '127.0.0.1' || clientIp === '::1' || clientIp === networkMonitor.currentIp;
        const rawPeers = discoveryEngine.getPeers();

        let peers = [];
        if (isLocalhost) {
            // For laptop viewing: show only external devices (phone, friend's laptop)
            peers = rawPeers.filter(p => p.id !== discoveryEngine.deviceId && p.ip !== '127.0.0.1' && p.ip !== networkMonitor.currentIp);
        } else {
            // For remote phone scanning: include the Host Laptop so the phone radar sees this laptop!
            const hostPeer = {
                id: discoveryEngine.deviceId,
                name: discoveryEngine.deviceName,
                deviceType: discoveryEngine.deviceType,
                osType: discoveryEngine.osType,
                avatar: discoveryEngine.avatar,
                ip: networkMonitor.currentIp,
                httpPort: discoveryEngine.httpPort,
                url: `http://${networkMonitor.currentIp}:${discoveryEngine.httpPort}`,
                isHost: true,
                lastSeen: Date.now()
            };
            peers = [hostPeer, ...rawPeers.filter(p => p.id !== discoveryEngine.deviceId && p.ip !== clientIp)];
        }

        res.json({
            success: true,
            peers
        });
    });

    router.post('/peers/manual', (req, res) => {
        const { ip, port, name } = req.body;
        if (!ip || !port) {
            return res.status(400).json({ success: false, error: 'IP and port are required' });
        }
        const peer = discoveryEngine.manualAddPeer(ip, port, name);
        res.json({ success: true, peer });
    });

    // 3. QR Code generator for Local Wi-Fi & Hotspot pairing
    router.get('/qr', async (req, res) => {
        try {
            const ifaces = getNetworkInterfaces();
            const requestedIp = req.query.ip;
            const primaryIp = requestedIp || getPrimaryIp();
            const connectUrl = `http://${primaryIp}:${discoveryEngine.httpPort}`;

            const qrDataUrl = await QRCode.toDataURL(connectUrl, {
                width: 320,
                margin: 2,
                color: {
                    dark: '#00f2fe',
                    light: '#0a0e17'
                }
            });

            res.json({
                success: true,
                url: connectUrl,
                selectedIp: primaryIp,
                interfaces: ifaces,
                qrCode: qrDataUrl
            });
        } catch (err) {
            res.status(500).json({ success: false, error: err.message });
        }
    });

    // 4. Transfer & Worker Control
    router.post('/transfer/start', (req, res) => {
        const { filePath, targetPeers, fileName, fileSize } = req.body;

        if (!filePath || !fs.existsSync(filePath)) {
            return res.status(400).json({ success: false, error: 'File path does not exist on host' });
        }

        if (!targetPeers || !Array.isArray(targetPeers) || targetPeers.length === 0) {
            return res.status(400).json({ success: false, error: 'At least one target peer must be specified' });
        }

        const stats = fs.statSync(filePath);
        const fileObj = {
            id: `f_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
            name: fileName || path.basename(filePath),
            path: filePath,
            size: fileSize || stats.size
        };

        const workers = workerPool.dispatchTransfer({
            file: fileObj,
            targetPeers,
            senderName: discoveryEngine.deviceName
        });

        res.json({
            success: true,
            message: `Dispatched ${workers.length} transfer worker(s) for high-speed streaming`,
            workers
        });
    });

    router.get('/workers', (req, res) => {
        res.json({
            success: true,
            workers: workerPool.getAllWorkers()
        });
    });

    router.post('/transfer/cancel/:id', (req, res) => {
        const fileId = req.params.id;
        workerPool.cancelWorker(fileId);
        vaultManager.cancelUpload(fileId);
        broadcastWs('transfer_cancelled', { fileId });
        res.json({ success: true, message: `Transfer ${fileId} cancelled` });
    });

    router.post('/workers/:id/pause', (req, res) => {
        workerPool.pauseWorker(req.params.id);
        res.json({ success: true });
    });

    router.post('/workers/:id/resume', (req, res) => {
        workerPool.resumeWorker(req.params.id);
        res.json({ success: true });
    });

    router.post('/workers/:id/cancel', (req, res) => {
        workerPool.cancelWorker(req.params.id);
        res.json({ success: true });
    });

    // 5. App Vault Ingest (Receiving Chunks via Worker stream)
    router.post('/vault/upload-chunk', express.raw({ type: '*/*', limit: '200mb' }), async (req, res) => {
        try {
            const fileId = req.headers['x-file-id'] || req.query.fileId;
            const fileName = decodeURIComponent(req.headers['x-file-name'] || req.query.fileName || 'file');
            const fileSize = Number(req.headers['x-file-size'] || req.query.fileSize);
            const chunkIndex = Number(req.headers['x-chunk-index'] || req.query.chunkIndex);
            const totalChunks = Number(req.headers['x-total-chunks'] || req.query.totalChunks);
            const startByte = Number(req.headers['x-chunk-start'] || req.query.startByte || (chunkIndex * (req.body ? req.body.length : 0)));
            const senderId = req.headers['x-sender-id'] || req.query.senderId || null;
            const senderName = decodeURIComponent(req.headers['x-sender-name'] || req.query.senderName || 'Sender');
            const targetPeerId = req.headers['x-target-peer-id'] || req.query.targetPeerId || null;
            const targetPeerName = decodeURIComponent(req.headers['x-target-peer'] || req.query.targetPeerName || 'All Devices');

            if (!fileId || isNaN(chunkIndex) || isNaN(totalChunks)) {
                return res.status(400).json({ success: false, error: 'Missing chunk metadata headers' });
            }

            let chunkBuffer = Buffer.isBuffer(req.body) ? req.body : null;
            if (!chunkBuffer || chunkBuffer.length === 0) {
                const chunks = [];
                for await (const chunk of req) {
                    chunks.push(chunk);
                }
                chunkBuffer = Buffer.concat(chunks);
            }

            const result = await vaultManager.handleChunk({
                fileId,
                fileName,
                fileSize,
                chunkIndex,
                totalChunks,
                startByte,
                senderId,
                senderName,
                targetPeerId,
                targetPeerName,
                chunkBuffer
            });

            res.json({ success: true, ...result });
        } catch (err) {
            console.error('[Vault] Chunk ingestion error:', err);
            res.status(500).json({ success: false, error: err.message });
        }
    });

    // Direct upload for web browser clients (Phone dropping file on web page)
    router.post('/vault/direct-upload', upload.single('file'), async (req, res) => {
        try {
            if (!req.file) {
                return res.status(400).json({ success: false, error: 'No file uploaded' });
            }

            const senderName = req.body.senderName || 'Web Client / Phone';
            const tempPath = req.file.path;
            const originalName = req.file.originalname;

            const cleanName = path.basename(originalName).replace(/[^a-zA-Z0-9._-]/g, '_');
            const finalFileName = `${Date.now()}_${cleanName}`;
            const finalFilePath = path.join(vaultManager.vaultDir, finalFileName);

            fs.renameSync(tempPath, finalFilePath);

            const stats = fs.statSync(finalFilePath);
            const crypto = require('crypto');
            const hash = await require('../transfer/checksum').computeFileHash(finalFilePath);

            const vaultItem = {
                id: `upload_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
                originalName,
                vaultFileName: finalFileName,
                path: finalFilePath,
                size: stats.size,
                category: vaultManager.categorizeFile(originalName),
                senderName,
                hash,
                receivedAt: new Date().toISOString(),
                isExported: false,
                exportedPaths: []
            };

            vaultManager.files.unshift(vaultItem);
            vaultManager._saveIndex();
            vaultManager.emit('file_received', vaultItem);

            res.json({
                success: true,
                message: 'File stored in App Vault',
                item: vaultItem
            });
        } catch (err) {
            console.error('[Vault] Direct upload error:', err);
            res.status(500).json({ success: false, error: err.message });
        }
    });

    router.post('/vault/upload-direct', upload.single('file'), async (req, res) => {
        try {
            if (!req.file) {
                return res.status(400).json({ success: false, error: 'No file uploaded' });
            }

            const senderName = req.body.senderName || 'Web Client / Phone';
            const tempPath = req.file.path;
            const originalName = req.file.originalname;

            const cleanName = path.basename(originalName).replace(/[^a-zA-Z0-9._-]/g, '_');
            const finalFileName = `${Date.now()}_${cleanName}`;
            const finalFilePath = path.join(vaultManager.vaultDir, finalFileName);

            fs.renameSync(tempPath, finalFilePath);

            const stats = fs.statSync(finalFilePath);
            const hash = await require('../transfer/checksum').computeFileHash(finalFilePath);

            const vaultItem = {
                id: `upload_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
                originalName,
                vaultFileName: finalFileName,
                path: finalFilePath,
                size: stats.size,
                category: vaultManager.categorizeFile(originalName),
                senderName,
                hash,
                receivedAt: new Date().toISOString(),
                isExported: false,
                exportedPaths: []
            };

            vaultManager.files.unshift(vaultItem);
            vaultManager._saveIndex();
            vaultManager.emit('file_received', vaultItem);

            res.json({
                success: true,
                message: 'File stored in App Vault',
                item: vaultItem
            });
        } catch (err) {
            console.error('[Vault] Upload direct error:', err);
            res.status(500).json({ success: false, error: err.message });
        }
    });

    // 6. App Vault Management
    router.get('/vault/items', (req, res) => {
        const { category, search } = req.query;
        const items = vaultManager.getVaultItems({ category, search });
        res.json({ success: true, items });
    });

    router.get('/vault/stats', (req, res) => {
        res.json({ success: true, stats: vaultManager.getVaultStats() });
    });

    router.get('/vault/preview/:id', (req, res) => {
        const item = vaultManager.getVaultItemById(req.params.id);
        if (!item || !fs.existsSync(item.path)) {
            return res.status(404).send('File not found in Vault');
        }

        const ext = path.extname(item.originalName).toLowerCase().replace('.', '');
        const mimeMap = {
            pdf: 'application/pdf',
            png: 'image/png',
            jpg: 'image/jpeg',
            jpeg: 'image/jpeg',
            gif: 'image/gif',
            webp: 'image/webp',
            svg: 'image/svg+xml',
            mp4: 'video/mp4',
            webm: 'video/webm',
            mkv: 'video/x-matroska',
            mov: 'video/quicktime',
            mp3: 'audio/mpeg',
            wav: 'audio/wav',
            ogg: 'audio/ogg',
            m4a: 'audio/mp4',
            txt: 'text/plain; charset=utf-8',
            md: 'text/markdown; charset=utf-8',
            json: 'application/json',
            html: 'text/html; charset=utf-8'
        };

        const contentType = mimeMap[ext] || 'application/octet-stream';

        // Support video/audio streaming with HTTP Range headers
        const stat = fs.statSync(item.path);
        const fileSize = stat.size;
        const range = req.headers.range;

        if (range) {
            const parts = range.replace(/bytes=/, '').split('-');
            const start = parseInt(parts[0], 10);
            const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
            const chunkSize = (end - start) + 1;
            const fileStream = fs.createReadStream(item.path, { start, end });
            const head = {
                'Content-Range': `bytes ${start}-${end}/${fileSize}`,
                'Accept-Ranges': 'bytes',
                'Content-Length': chunkSize,
                'Content-Type': contentType,
            };
            res.writeHead(206, head);
            fileStream.pipe(res);
        } else {
            const head = {
                'Content-Length': fileSize,
                'Content-Type': contentType,
                'Content-Disposition': `inline; filename="${encodeURIComponent(item.originalName)}"`
            };
            res.writeHead(200, head);
            fs.createReadStream(item.path).pipe(res);
        }
    });

    router.get('/vault/download/:id', (req, res) => {
        const item = vaultManager.getVaultItemById(req.params.id);
        if (!item || !fs.existsSync(item.path)) {
            return res.status(404).send('File not found in Vault');
        }
        res.download(item.path, item.originalName);
    });

    router.post('/vault/export/:id', (req, res) => {
        try {
            const { targetDirectory } = req.body;
            const result = exportFileToStorage(req.params.id, targetDirectory);
            res.json({ success: true, result });
        } catch (err) {
            res.status(400).json({ success: false, error: err.message });
        }
    });

    router.post('/vault/batch-export', (req, res) => {
        try {
            const { ids, targetDirectory } = req.body;
            if (!ids || !Array.isArray(ids)) {
                return res.status(400).json({ success: false, error: 'Array of ids required' });
            }
            const results = batchExportToStorage(ids, targetDirectory);
            res.json({ success: true, results });
        } catch (err) {
            res.status(500).json({ success: false, error: err.message });
        }
    });

    router.delete('/vault/item/:id', (req, res) => {
        const success = vaultManager.deleteVaultItem(req.params.id);
        res.json({ success });
    });

    router.delete('/vault/clear', (req, res) => {
        vaultManager.clearVault();
        res.json({ success: true });
    });

    // 7. System Storage Directories
    router.get('/system/directories', (req, res) => {
        res.json({
            success: true,
            directories: getSystemDirectories()
        });
    });

    // 8. Instant Text & Link Sync
    router.post('/sync/clipboard', (req, res) => {
        const { text, senderId, senderName, targetPeerIds, targetPeerNames } = req.body;
        if (!text || !text.trim()) {
            return res.status(400).json({ success: false, error: 'Text cannot be empty' });
        }

        const syncItem = {
            id: `clip_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
            text: text.trim(),
            senderId: senderId || 'unknown',
            senderName: senderName || discoveryEngine.deviceName,
            targetPeerIds: (targetPeerIds && targetPeerIds.length > 0) ? targetPeerIds : ['all'],
            targetPeerNames: (targetPeerNames && targetPeerNames.length > 0) ? targetPeerNames : ['All Devices'],
            timestamp: new Date().toISOString(),
            isUrl: /^https?:\/\//i.test(text.trim())
        };

        vaultManager.addClipboardItem(syncItem);

        if (discoveryEngine.emit) {
            discoveryEngine.emit('clipboard_synced', syncItem);
        }

        res.json({ success: true, syncItem });
    });

    router.get('/sync/clipboard/history', (req, res) => {
        res.json({ success: true, history: vaultManager.getClipboardHistory() });
    });

    return router;
}

module.exports = createApiRouter;
