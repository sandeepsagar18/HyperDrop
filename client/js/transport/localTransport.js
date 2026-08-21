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

    async connect(clientInfo = {}) {
        this.status = 'connecting';
        console.log(`[CONNECTION] Mode: LOCAL | Connecting to ${this.peer.name} (${this.peer.url})`);

        try {
            const hsRes = await fetch(`${this.peer.url || ''}/api/handshake`, {
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
            const statusRes = await fetch(`${this.peer.url || ''}/api/vault/upload-status/${fileId}`);
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
        const { fileId, fileName, fileSize, chunkIndex, totalChunks, startByte, senderId, senderName } = chunkMeta;

        const uploadUrl = `/api/vault/upload-chunk?fileId=${encodeURIComponent(fileId)}&fileName=${encodeURIComponent(fileName)}&fileSize=${fileSize}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}&startByte=${startByte}&senderId=${encodeURIComponent(senderId)}&senderName=${encodeURIComponent(senderName)}&targetPeerId=${encodeURIComponent(this.peer.id)}&targetPeerName=${encodeURIComponent(this.peer.name || 'Device')}`;

        let chunkUploaded = false;
        let retryCount = 0;
        const maxRetries = 4;

        while (!chunkUploaded && retryCount < maxRetries) {
            try {
                const res = await fetch(uploadUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/octet-stream',
                        'X-File-Id': fileId,
                        'X-Chunk-Index': String(chunkIndex),
                        'X-Total-Chunks': String(totalChunks),
                        'X-Chunk-Start': String(startByte),
                        'X-File-Name': encodeURIComponent(fileName),
                        'X-File-Size': String(fileSize),
                        'X-Sender-Id': senderId,
                        'X-Sender-Name': encodeURIComponent(senderName),
                        'X-Target-Peer-Id': this.peer.id,
                        'X-Target-Peer': encodeURIComponent(this.peer.name || 'Device'),
                        'X-Session-Token': this.sessionToken
                    },
                    body: chunkBlob
                });

                if (!res.ok) {
                    const errText = await res.text();
                    throw new Error(`HTTP ${res.status}: ${errText}`);
                }
                chunkUploaded = true;
                return { success: true };
            } catch (err) {
                retryCount++;
                console.warn(`[TRANSFER] Chunk ${chunkIndex}/${totalChunks} retry ${retryCount}/${maxRetries}: ${err.message}`);
                if (retryCount >= maxRetries) {
                    throw err;
                }
                await new Promise(r => setTimeout(r, 250 * retryCount));
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
