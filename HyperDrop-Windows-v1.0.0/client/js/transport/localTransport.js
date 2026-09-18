/**
 * LocalTransport
 * Implements high-speed local HTTP chunk streaming for Same Wi-Fi and Offline Hotspot networks.
 * Uses 4MB chunks for maximum local throughput (50-100+ MB/s) with zero cloud dependencies.
 */
class LocalTransport extends TransferTransport {
    constructor(peer, options = {}) {
        super(options);
        this.peer = peer;
        this.mode = 'local';
        this.sessionToken = 'hd_local_default';
        this.chunkSize = options.chunkSize || (4 * 1024 * 1024); // 4MB
    }

    _resolveBaseUrl() {
        // In HyperDrop architecture, chunk streaming routes through the central host server vault.
        // If window.app.serverBaseUrl is configured (e.g. from APK or browser), use it.
        if (typeof window !== 'undefined') {
            if (window.app && window.app.serverBaseUrl && window.app.serverBaseUrl.startsWith('http')) {
                return window.app.serverBaseUrl.replace(/\/+$/, '');
            }
            if (window.location && window.location.origin && window.location.origin.startsWith('http') && !window.location.origin.startsWith('file:')) {
                return window.location.origin.replace(/\/+$/, '');
            }
            if (window.app && window.app.systemStatus && window.app.systemStatus.primaryIp) {
                const port = window.app.systemStatus.httpPort || 3000;
                return `http://${window.app.systemStatus.primaryIp}:${port}`;
            }
        }
        return 'http://127.0.0.1:3000';
    }

    async connect(clientInfo = {}) {
        this.status = 'connecting';
        const baseUrl = this._resolveBaseUrl();
        console.log(`[CONNECTION] Mode: LOCAL | Connecting to ${this.peer.name} (${baseUrl || 'local'})`);

        try {
            const hsRes = await fetch(`${baseUrl}/api/handshake`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    deviceId: clientInfo.clientId,
                    deviceName: clientInfo.clientName,
                    protocolVersion: 1,
                    appType: 'HyperDrop'
                })
            });

            const hsData = await hsRes.json();
            if (hsData && hsData.sessionToken) {
                this.sessionToken = hsData.sessionToken;
                if (hsData.maxChunkSize) {
                    this.chunkSize = hsData.maxChunkSize;
                }
                console.log(`[HANDSHAKE] Handshake accepted by ${this.peer.name} | Token: ${this.sessionToken.substring(0, 10)}...`);
            }
            this.status = 'connected';
            return { success: true, mode: 'local' };
        } catch (err) {
            console.warn(`[LOCAL] Handshake warning (proceeding with local direct streaming):`, err.message);
            this.status = 'connected';
            return { success: true, mode: 'local' };
        }
    }

    async checkResumeStatus(fileId) {
        try {
            const baseUrl = this._resolveBaseUrl();
            const statusRes = await fetch(`${baseUrl}/api/vault/upload-status/${fileId}`);
            const data = await statusRes.json();
            if (data && data.status && data.status.nextChunkIndex > 0) {
                return {
                    startChunkIndex: data.status.nextChunkIndex,
                    completedChunks: data.status.completedChunks || []
                };
            }
        } catch (e) {}
        return { startChunkIndex: 0, completedChunks: [] };
    }

    async sendChunk(chunkBlob, chunkMeta) {
        const { fileId, fileName, fileSize, chunkIndex, totalChunks, startByte, senderId, senderName, signal } = chunkMeta;
        const baseUrl = this._resolveBaseUrl();

        const uploadUrl = `${baseUrl}/api/vault/upload-chunk?fileId=${encodeURIComponent(fileId)}&fileName=${encodeURIComponent(fileName)}&fileSize=${fileSize}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}&startByte=${startByte}&senderId=${encodeURIComponent(senderId)}&senderName=${encodeURIComponent(senderName)}&targetPeerId=${encodeURIComponent(this.peer.id || '')}&targetPeerName=${encodeURIComponent(this.peer.name || 'Device')}`;

        let chunkUploaded = false;
        let retryCount = 0;
        const maxRetries = 8;

        while (!chunkUploaded && retryCount < maxRetries) {
            if (signal && signal.aborted) {
                return { cancelled: true };
            }

            // Create per-chunk timeout controller (45 seconds per chunk)
            const timeoutController = new AbortController();
            const timeoutId = setTimeout(() => timeoutController.abort(), 45000);

            // Link parent abort signal if present
            const onParentAbort = () => timeoutController.abort();
            if (signal) signal.addEventListener('abort', onParentAbort, { once: true });

            try {
                const res = await fetch(uploadUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/octet-stream',
                        'X-File-Id': String(fileId),
                        'X-Chunk-Index': String(chunkIndex),
                        'X-Total-Chunks': String(totalChunks),
                        'X-Chunk-Start': String(startByte)
                    },
                    body: chunkBlob,
                    signal: timeoutController.signal
                });

                clearTimeout(timeoutId);
                if (signal) signal.removeEventListener('abort', onParentAbort);

                if (!res.ok) {
                    const errText = await res.text().catch(() => '');
                    throw new Error(`HTTP ${res.status}: ${errText}`);
                }
                chunkUploaded = true;
                return { success: true };
            } catch (err) {
                clearTimeout(timeoutId);
                if (signal) signal.removeEventListener('abort', onParentAbort);

                if (signal && signal.aborted) {
                    return { cancelled: true };
                }
                retryCount++;
                console.warn(`[TRANSFER] Chunk ${chunkIndex}/${totalChunks} retry ${retryCount}/${maxRetries}: ${err.message}`);
                if (retryCount >= maxRetries) {
                    throw err;
                }
                // Adaptive backoff before retrying this chunk
                await new Promise(r => setTimeout(r, Math.min(2000, 300 * retryCount)));
            }
        }
    }
}

if (typeof window !== 'undefined') {
    window.LocalTransport = LocalTransport;
}
if (typeof module !== 'undefined') {
    module.exports = LocalTransport;
}
