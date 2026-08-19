/**
 * Base TransferTransport Interface
 * Common interface for both Local HTTP Streaming and Remote WebRTC DataChannel transfers.
 */
class TransferTransport {
    constructor(options = {}) {
        this.options = options;
        this.status = 'idle'; // 'idle' | 'connecting' | 'connected' | 'streaming' | 'paused' | 'completed' | 'failed'
        this.transferId = null;
        this.mode = 'abstract'; // 'local' | 'webrtc-p2p' | 'webrtc-turn'
    }

    async connect() {
        throw new Error('connect() must be implemented by transport');
    }

    async sendMetadata(metadata) {
        throw new Error('sendMetadata() must be implemented by transport');
    }

    async sendChunk(chunkData, chunkMeta) {
        throw new Error('sendChunk() must be implemented by transport');
    }

    async checkResumeStatus(fileId) {
        return { startChunkIndex: 0, completedChunks: [] };
    }

    pause() {
        this.status = 'paused';
    }

    resume() {
        this.status = 'streaming';
    }

    close() {
        this.status = 'idle';
    }

    getStats() {
        return { mode: this.mode, status: this.status };
    }
}

if (typeof window !== 'undefined') {
    window.TransferTransport = TransferTransport;
}
if (typeof module !== 'undefined') {
    module.exports = TransferTransport;
}
