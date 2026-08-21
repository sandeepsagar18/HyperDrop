/**
 * WebRTCTransport
 * Ultra-high-performance peer-to-peer file transfer over WebRTC DataChannel.
 * 
 * Connection Classifications (Based on active selected ICE candidate pair):
 *  - CASE 1: host <-> host               => "Local P2P Connect" (Same Wi-Fi / Hotspot)
 *  - CASE 2: srflx <-> srflx / prflx      => "Remote P2P Connect" (Across Internet / NAT via STUN)
 *  - CASE 3: relay                        => "Remote Relay" (TURN fallback)
 * 
 * Performance Optimizations:
 *  - Buffered ICE candidate queueing to prevent host candidate drops from race conditions
 *  - Pipelined 64KB binary packet transmission over RTCDataChannel.send()
 *  - Continuous 2MB SCTP kernel buffer saturation with bufferedAmountLowThreshold
 *  - Zero DOM thrashing on receiver (throttled UI dispatch)
 *  - ZERO server-side file relay (no WebSocket file data, no HTTP upload, no Render disk)
 */
class WebRTCTransport extends TransferTransport {
    constructor(peer, ws, options = {}) {
        super(options);
        this.peer = peer; // { id, name, sessionId, isHost, isRemote }
        this.ws = ws; // WebSocket for signaling
        this.peerConnection = null;
        this.dataChannel = null;
        this.clientId = options.clientId || null;
        this.clientName = options.clientName || 'Device';
        
        this.mode = 'webrtc-p2p';
        this.connectionClassification = 'Detecting...';
        this.pendingIceCandidates = []; // Prevents race condition dropping host candidates before remoteDescription
        
        this.connectionStats = {
            classification: 'Detecting...',
            localCandidateType: 'unknown',
            remoteCandidateType: 'unknown',
            candidatePair: 'Detecting...',
            protocol: 'udp',
            currentRoundTripTime: 0,
            availableOutgoingBitrate: null,
            availableIncomingBitrate: null
        };

        this.chunkSize = options.chunkSize || (64 * 1024); // 64KB optimal WebRTC DataChannel packet size
        this.maxBufferThreshold = options.maxBufferThreshold || (2 * 1024 * 1024); // 2MB kernel pipeline buffer
        this.isHost = options.isHost !== false;
        this.iceConfig = options.iceConfig || {
            iceServers: [
                { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302', 'stun:global.stun.twilio.com:3478'] }
            ]
        };

        this.incomingTransfers = new Map(); // numericId -> transferData
        this.fileIdToNumeric = new Map();
        this.numericToFileId = new Map();
    }

    async connect(clientInfo = {}) {
        this.status = 'connecting';
        if (clientInfo.clientId) this.clientId = clientInfo.clientId;
        if (clientInfo.clientName) this.clientName = clientInfo.clientName;

        console.log(`[WEBRTC] Initializing Peer Connection for ${this.peer.name} (${this.peer.id}) | Host: ${this.isHost}`);

        return new Promise((resolve, reject) => {
            try {
                this.peerConnection = new RTCPeerConnection(this.iceConfig);

                this.peerConnection.onicecandidate = (event) => {
                    if (event.candidate && this.ws && this.ws.readyState === 1) {
                        this.ws.send(JSON.stringify({
                            type: 'webrtc_ice_candidate',
                            data: {
                                sessionId: this.peer.sessionId || null,
                                targetPeerId: this.peer.id,
                                senderId: this.clientId,
                                candidate: event.candidate
                            }
                        }));
                    }
                };

                this.peerConnection.oniceconnectionstatechange = () => {
                    const state = this.peerConnection.iceConnectionState;
                    console.log(`[WEBRTC] ICE Connection State with ${this.peer.name}: ${state}`);
                    if (state === 'connected' || state === 'completed') {
                        this.detectConnectionMode();
                    } else if (state === 'failed') {
                        console.warn('[WEBRTC] ICE Connection failed. Checking fallback...');
                        this.connectionClassification = 'Remote Relay';
                    }
                };

                this.peerConnection.onconnectionstatechange = () => {
                    console.log(`[WEBRTC] Connection State: ${this.peerConnection.connectionState}`);
                    if (this.peerConnection.connectionState === 'connected') {
                        this.detectConnectionMode();
                    }
                };

                if (this.isHost) {
                    this.dataChannel = this.peerConnection.createDataChannel('hyperdrop-transfer', {
                        ordered: true
                    });
                    this._setupDataChannel(this.dataChannel, resolve, reject);
                    this._createOffer();
                } else {
                    this.peerConnection.ondatachannel = (event) => {
                        this.dataChannel = event.channel;
                        this._setupDataChannel(this.dataChannel, resolve, reject);
                    };
                }

                setTimeout(() => {
                    if (this.status !== 'connected' && this.status !== 'failed') {
                        console.warn(`[WEBRTC] Connection still pending after timeout for ${this.peer.name}`);
                    }
                }, 12000);

            } catch (err) {
                this.status = 'failed';
                reject(err);
            }
        });
    }

    async detectConnectionMode() {
        if (!this.peerConnection) return this.connectionStats;
        try {
            const stats = await this.peerConnection.getStats();
            let selectedPair = null;
            let localCandidate = null;
            let remoteCandidate = null;

            stats.forEach(report => {
                if (report.type === 'candidate-pair' && (report.state === 'succeeded' || report.selected || report.nominated)) {
                    selectedPair = report;
                }
            });

            if (selectedPair) {
                localCandidate = stats.get(selectedPair.localCandidateId);
                remoteCandidate = stats.get(selectedPair.remoteCandidateId);
            }

            const localType = localCandidate ? localCandidate.candidateType : 'unknown';
            const remoteType = remoteCandidate ? remoteCandidate.candidateType : 'unknown';
            const protocol = selectedPair ? (selectedPair.protocol || 'udp') : 'udp';
            const rtt = selectedPair && selectedPair.currentRoundTripTime ? Math.round(selectedPair.currentRoundTripTime * 1000) : 0;
            const availableOutgoingBitrate = selectedPair ? selectedPair.availableOutgoingBitrate : null;
            const availableIncomingBitrate = selectedPair ? selectedPair.availableIncomingBitrate : null;

            // Strict Connection Classification based on selected ICE candidate types
            let classification = 'Remote P2P Connect';
            if (localType === 'host' && remoteType === 'host') {
                classification = 'Local P2P Connect';
            } else if (localType === 'relay' || remoteType === 'relay') {
                classification = 'Remote Relay';
            } else {
                classification = 'Remote P2P Connect';
            }

            this.connectionClassification = classification;
            this.connectionStats = {
                classification,
                localCandidateType: localType,
                remoteCandidateType: remoteType,
                candidatePair: `${localType} (${localCandidate ? (localCandidate.address || localCandidate.ip) : '?'}) ↔ ${remoteType} (${remoteCandidate ? (remoteCandidate.address || remoteCandidate.ip) : '?'})`,
                protocol,
                currentRoundTripTime: rtt,
                availableOutgoingBitrate,
                availableIncomingBitrate,
                isDirectLan: localType === 'host' && remoteType === 'host',
                isRelay: localType === 'relay' || remoteType === 'relay'
            };

            console.log(`[WEBRTC STATS] Classification: ${classification} | Local: ${localType} | Remote: ${remoteType} | RTT: ${rtt}ms | OutgoingBitrate: ${availableOutgoingBitrate || 'N/A'}`);
        } catch (e) {
            console.error('[WEBRTC] Error querying getStats:', e);
        }
        return this.connectionStats;
    }

    _setupDataChannel(channel, resolve, reject) {
        channel.binaryType = 'arraybuffer';
        channel.bufferedAmountLowThreshold = 512 * 1024; // 512KB low threshold for non-blocking backpressure

        channel.onopen = async () => {
            this.status = 'connected';
            await this.detectConnectionMode();
            console.log(`[WEBRTC] Direct DataChannel opened with ${this.peer.name} [Classification: ${this.connectionClassification}]`);
            if (resolve) resolve({ success: true, classification: this.connectionClassification, stats: this.connectionStats });
        };

        channel.onclose = () => {
            this.status = 'idle';
            console.log(`[WEBRTC] DataChannel closed with ${this.peer.name}`);
        };

        channel.onerror = (err) => {
            console.error('[WEBRTC] DataChannel error:', err);
            this.status = 'failed';
            if (reject) reject(err);
        };

        channel.onmessage = (event) => {
            this._handleDataChannelMessage(event.data);
        };
    }

    async _createOffer() {
        try {
            const offer = await this.peerConnection.createOffer();
            await this.peerConnection.setLocalDescription(offer);

            this.ws.send(JSON.stringify({
                type: 'webrtc_offer',
                data: {
                    sessionId: this.peer.sessionId || null,
                    targetPeerId: this.peer.id,
                    senderId: this.clientId,
                    senderName: this.clientName,
                    sdp: offer
                }
            }));
        } catch (err) {
            console.error('[WEBRTC] Error creating offer:', err);
        }
    }

    async handleRemoteOffer(sdp) {
        try {
            if (!this.peerConnection) {
                this.peerConnection = new RTCPeerConnection(this.iceConfig);
            }
            await this.peerConnection.setRemoteDescription(new RTCSessionDescription(sdp));
            
            // Drain buffered ICE candidates received before remoteDescription
            await this._drainPendingIceCandidates();

            const answer = await this.peerConnection.createAnswer();
            await this.peerConnection.setLocalDescription(answer);

            this.ws.send(JSON.stringify({
                type: 'webrtc_answer',
                data: {
                    sessionId: this.peer.sessionId || null,
                    targetPeerId: this.peer.id,
                    senderId: this.clientId,
                    senderName: this.clientName,
                    sdp: answer
                }
            }));
        } catch (err) {
            console.error('[WEBRTC] Error handling offer:', err);
        }
    }

    async handleRemoteAnswer(sdp) {
        try {
            if (this.peerConnection) {
                await this.peerConnection.setRemoteDescription(new RTCSessionDescription(sdp));
                console.log(`[WEBRTC] Remote SDP Answer set successfully for ${this.peer.name}`);
                // Drain buffered ICE candidates
                await this._drainPendingIceCandidates();
            }
        } catch (err) {
            console.error('[WEBRTC] Error setting remote answer:', err);
        }
    }

    async handleRemoteIceCandidate(candidate) {
        try {
            if (!this.peerConnection || !this.peerConnection.remoteDescription || !this.peerConnection.remoteDescription.type) {
                // Buffer candidate until setRemoteDescription completes
                this.pendingIceCandidates.push(candidate);
                return;
            }
            await this.peerConnection.addIceCandidate(new RTCIceCandidate(candidate));
        } catch (err) {
            console.error('[WEBRTC] Error adding ICE candidate:', err);
        }
    }

    async _drainPendingIceCandidates() {
        if (!this.peerConnection || !this.pendingIceCandidates.length) return;
        const candidates = [...this.pendingIceCandidates];
        this.pendingIceCandidates = [];
        for (const cand of candidates) {
            try {
                await this.peerConnection.addIceCandidate(new RTCIceCandidate(cand));
            } catch (err) {}
        }
    }

    async _waitForBufferDrain() {
        if (!this.dataChannel || this.dataChannel.bufferedAmount < this.maxBufferThreshold) {
            return;
        }

        return new Promise((resolve) => {
            const onLow = () => {
                this.dataChannel.removeEventListener('bufferedamountlow', onLow);
                resolve();
            };
            this.dataChannel.addEventListener('bufferedamountlow', onLow);
        });
    }

    _getNumericId(fileId) {
        if (this.fileIdToNumeric.has(fileId)) return this.fileIdToNumeric.get(fileId);
        let hash = 0;
        for (let i = 0; i < fileId.length; i++) {
            hash = ((hash << 5) - hash) + fileId.charCodeAt(i);
            hash |= 0;
        }
        const numericId = Math.abs(hash);
        this.fileIdToNumeric.set(fileId, numericId);
        this.numericToFileId.set(numericId, fileId);
        return numericId;
    }

    async checkResumeStatus(fileId) {
        return { startChunkIndex: 0, completedChunks: [] };
    }

    async sendStartSignal(meta) {
        if (!this.dataChannel || this.dataChannel.readyState !== 'open') return;
        const numericId = this._getNumericId(meta.fileId);
        this.dataChannel.send(JSON.stringify({
            type: 'START_FILE_STREAM',
            numericId,
            fileId: meta.fileId,
            fileName: meta.fileName,
            fileSize: meta.fileSize,
            totalChunks: meta.totalChunks,
            senderName: meta.senderName || this.clientName
        }));
    }

    /**
     * High-speed direct streaming over RTCDataChannel.send()
     */
    async streamFile(file, meta, onProgress) {
        if (!this.dataChannel || this.dataChannel.readyState !== 'open') {
            throw new Error('DataChannel is not open');
        }

        const CHUNK_SIZE = this.chunkSize; // 64KB
        const totalChunks = Math.ceil(file.size / CHUNK_SIZE) || 1;
        const numericId = this._getNumericId(meta.fileId);

        // 1. Send metadata header
        await this.sendStartSignal({
            fileId: meta.fileId,
            fileName: meta.fileName,
            fileSize: file.size,
            totalChunks,
            senderName: meta.senderName || this.clientName
        });

        // 2. High-throughput chunk streaming with continuous buffer saturation
        let bytesTransferred = 0;
        const startTime = Date.now();
        let lastProgressTime = Date.now();
        let lastProgressBytes = 0;

        for (let i = 0; i < totalChunks; i++) {
            if (meta.isCancelled && meta.isCancelled()) {
                console.log(`[WEBRTC] Transfer cancelled by sender for ${meta.fileName}`);
                return;
            }

            // Wait only when SCTP buffer is saturated (above 2MB)
            if (this.dataChannel.bufferedAmount >= this.maxBufferThreshold) {
                await this._waitForBufferDrain();
            }

            const startByte = i * CHUNK_SIZE;
            const endByte = Math.min(startByte + CHUNK_SIZE, file.size);
            const chunkBlob = file.slice(startByte, endByte);
            const chunkBuf = await chunkBlob.arrayBuffer();

            // 16-Byte Header + Payload
            const packet = new Uint8Array(16 + chunkBuf.byteLength);
            const view = new DataView(packet.buffer);
            view.setUint32(0, numericId, false);
            view.setUint32(4, i, false);
            view.setUint32(8, totalChunks, false);
            view.setUint32(12, chunkBuf.byteLength, false);
            packet.set(new Uint8Array(chunkBuf), 16);

            // DIRECT RTCDataChannel.send() — ZERO SERVER INVOLVEMENT
            this.dataChannel.send(packet.buffer);

            bytesTransferred += chunkBuf.byteLength;

            const now = Date.now();
            const deltaMs = now - lastProgressTime;
            if (deltaMs >= 250 || i === totalChunks - 1) {
                const deltaBytes = bytesTransferred - lastProgressBytes;
                const elapsedSec = (now - startTime) / 1000;
                const instantaneousSpeedMBs = deltaMs > 0 ? (deltaBytes / (1024 * 1024) / (deltaMs / 1000)) : 0;
                const instantaneousSpeedMbps = deltaMs > 0 ? ((deltaBytes * 8) / (deltaMs / 1000) / 1000000) : 0;
                const averageSpeedMBs = elapsedSec > 0 ? (bytesTransferred / (1024 * 1024) / elapsedSec) : 0;
                const averageSpeedMbps = elapsedSec > 0 ? ((bytesTransferred * 8) / elapsedSec / 1000000) : 0;
                const percent = Math.min(100, Math.round((bytesTransferred / file.size) * 100));

                if (onProgress) {
                    onProgress({
                        bytesTransferred,
                        percent,
                        speedMBs: parseFloat(instantaneousSpeedMBs.toFixed(1)),
                        speedMbps: parseFloat(instantaneousSpeedMbps.toFixed(1)),
                        averageSpeedMBs: parseFloat(averageSpeedMBs.toFixed(1)),
                        averageSpeedMbps: parseFloat(averageSpeedMbps.toFixed(1)),
                        etaSeconds: instantaneousSpeedMBs > 0 ? Math.ceil((file.size - bytesTransferred) / (instantaneousSpeedMBs * 1024 * 1024)) : 0
                    });
                }

                lastProgressTime = now;
                lastProgressBytes = bytesTransferred;
            }
        }
    }

    async _handleDataChannelMessage(data) {
        try {
            // Text Message Control
            if (typeof data === 'string') {
                const msg = JSON.parse(data);
                if (msg.type === 'START_FILE_STREAM') {
                    console.log(`[WEBRTC] Receiving Direct P2P stream: ${msg.fileName} (${(msg.fileSize / 1024 / 1024).toFixed(2)} MB)`);
                    this.incomingTransfers.set(msg.numericId, {
                        numericId: msg.numericId,
                        fileId: msg.fileId,
                        fileName: msg.fileName,
                        fileSize: msg.fileSize,
                        totalChunks: msg.totalChunks,
                        chunks: new Array(msg.totalChunks),
                        chunksReceived: 0,
                        bytesReceived: 0,
                        senderName: msg.senderName,
                        startTime: Date.now(),
                        lastUiUpdate: Date.now()
                    });

                    if (window.app) {
                        window.app.handleIncomingProgress({
                            fileId: msg.fileId,
                            fileName: msg.fileName,
                            fileSize: msg.fileSize,
                            senderName: msg.senderName,
                            bytesTransferred: 0,
                            percent: 0,
                            speedMBs: 0.0,
                            speedMbps: 0.0,
                            connectionPath: this.connectionClassification
                        });
                    }
                } else if (msg.type === 'TRANSFER_COMPLETE_ACK') {
                    console.log(`[WEBRTC] Peer confirmed 100% receipt for ${msg.fileId}`);
                }
                return;
            }

            // High-Speed Binary Packet Header (16 bytes)
            const view = new DataView(data);
            const numericId = view.getUint32(0, false);
            const chunkIndex = view.getUint32(4, false);
            const totalChunks = view.getUint32(8, false);
            const payloadLen = view.getUint32(12, false);

            const transfer = this.incomingTransfers.get(numericId);
            if (!transfer) return;

            const chunkData = new Uint8Array(data, 16, payloadLen);
            transfer.chunks[chunkIndex] = chunkData;
            transfer.chunksReceived++;
            transfer.bytesReceived += payloadLen;

            // Throttled UI progress dispatch (every 200ms) to avoid mobile DOM thrashing
            const now = Date.now();
            if (window.app && (now - transfer.lastUiUpdate >= 200 || transfer.chunksReceived === totalChunks)) {
                transfer.lastUiUpdate = now;
                const elapsedSec = (now - transfer.startTime) / 1000;
                const speedMBs = elapsedSec > 0 ? parseFloat((transfer.bytesReceived / (1024 * 1024) / elapsedSec).toFixed(1)) : 0;
                const speedMbps = elapsedSec > 0 ? parseFloat(((transfer.bytesReceived * 8) / elapsedSec / 1000000).toFixed(1)) : 0;
                const percent = Math.min(100, Math.round((transfer.bytesReceived / transfer.fileSize) * 100));

                window.app.handleIncomingProgress({
                    fileId: transfer.fileId,
                    fileName: transfer.fileName,
                    fileSize: transfer.fileSize,
                    senderName: transfer.senderName,
                    bytesTransferred: transfer.bytesReceived,
                    percent,
                    speedMBs,
                    speedMbps,
                    connectionPath: this.connectionClassification
                });
            }

            // All chunks received -> Assemble File & Trigger Instant Direct Browser Download
            if (transfer.chunksReceived === totalChunks) {
                console.log(`[WEBRTC] Direct P2P assembly complete for "${transfer.fileName}"! Triggering download...`);
                const fullBlob = new Blob(transfer.chunks);
                transfer.chunks = null; // Free memory
                
                this._saveReceivedFile(transfer, fullBlob);

                if (this.dataChannel && this.dataChannel.readyState === 'open') {
                    this.dataChannel.send(JSON.stringify({
                        type: 'TRANSFER_COMPLETE_ACK',
                        fileId: transfer.fileId
                    }));
                }

                this.incomingTransfers.delete(numericId);
            }

        } catch (err) {
            console.error('[WEBRTC] Error processing incoming DataChannel packet:', err);
        }
    }

    _saveReceivedFile(transfer, blob) {
        // Direct browser download for mobile phone / laptop (ZERO CLOUD RELAY)
        const downloadUrl = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = downloadUrl;
        a.download = transfer.fileName;
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
            document.body.removeChild(a);
            URL.revokeObjectURL(downloadUrl);
        }, 10000);

        if (window.app) {
            window.app.showToast(`📥 Received & Downloaded ${transfer.fileName}!`);
        }
    }

    close() {
        if (this.dataChannel) {
            try { this.dataChannel.close(); } catch (e) {}
        }
        if (this.peerConnection) {
            try { this.peerConnection.close(); } catch (e) {}
        }
        this.status = 'idle';
    }
}

if (typeof window !== 'undefined') {
    window.WebRTCTransport = WebRTCTransport;
}
if (typeof module !== 'undefined') {
    module.exports = WebRTCTransport;
}

