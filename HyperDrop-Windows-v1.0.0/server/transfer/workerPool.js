const { EventEmitter } = require('events');
const http = require('http');
const fs = require('fs');
const path = require('path');

/**
 * Transfer Worker Model
 * Represents a dedicated execution unit assigned to stream a file to a specific recipient.
 */
class TransferWorker extends EventEmitter {
    constructor({ id, file, targetPeer, chunkSize = 4 * 1024 * 1024 }) {
        super();
        this.id = id;
        this.file = file; // { path, name, size, type, hash }
        this.targetPeer = targetPeer; // { id, name, ip, httpPort, url }
        this.chunkSize = chunkSize; // 4MB default chunk size for high-speed local stream
        this.bytesTransferred = 0;
        this.totalBytes = file.size;
        this.status = 'queued'; // queued, streaming, paused, completed, failed, cancelled
        this.startTime = null;
        this.endTime = null;
        this.speedBytesPerSec = 0;
        this.lastSpeedCheckTime = null;
        this.lastSpeedCheckBytes = 0;
        this.errorMessage = null;
        this._isPaused = false;
        this._isCancelled = false;
        this._currentReq = null;
    }

    async start() {
        this.status = 'streaming';
        this.startTime = Date.now();
        this.lastSpeedCheckTime = Date.now();
        this.lastSpeedCheckBytes = 0;
        this.emit('status_change', this.getInfo());

        try {
            const totalChunks = Math.ceil(this.totalBytes / this.chunkSize) || 1;

            for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
                if (this._isCancelled) {
                    this.status = 'cancelled';
                    this.emit('status_change', this.getInfo());
                    return;
                }

                while (this._isPaused) {
                    await new Promise(r => setTimeout(r, 200));
                    if (this._isCancelled) {
                        this.status = 'cancelled';
                        this.emit('status_change', this.getInfo());
                        return;
                    }
                }

                const startByte = chunkIndex * this.chunkSize;
                const endByte = Math.min(startByte + this.chunkSize, this.totalBytes);
                const chunkLength = endByte - startByte;

                await this._sendChunk(chunkIndex, totalChunks, startByte, endByte, chunkLength);

                this.bytesTransferred += chunkLength;
                this._updateSpeed();
                this.emit('progress', this.getInfo());
            }

            this.status = 'completed';
            this.endTime = Date.now();
            this.emit('status_change', this.getInfo());
        } catch (err) {
            this.status = 'failed';
            this.errorMessage = err.message;
            this.endTime = Date.now();
            this.emit('error', { workerId: this.id, error: err.message });
            this.emit('status_change', this.getInfo());
        }
    }

    _sendChunk(chunkIndex, totalChunks, startByte, endByte, chunkLength) {
        return new Promise((resolve, reject) => {
            const buffer = Buffer.alloc(chunkLength);
            const fd = fs.openSync(this.file.path, 'r');
            fs.readSync(fd, buffer, 0, chunkLength, startByte);
            fs.closeSync(fd);

            const boundary = '----HyperDropBoundary' + Date.now();
            const header = `--${boundary}\r\n` +
                `Content-Disposition: form-data; name="file"; filename="${encodeURIComponent(this.file.name)}"\r\n` +
                `Content-Type: application/octet-stream\r\n\r\n`;
            const footer = `\r\n--${boundary}--\r\n`;

            const reqOptions = {
                hostname: this.targetPeer.ip,
                port: this.targetPeer.httpPort,
                path: `/api/vault/upload-chunk?fileId=${encodeURIComponent(this.file.id || this.id)}&fileName=${encodeURIComponent(this.file.name)}&fileSize=${this.totalBytes}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}&senderName=${encodeURIComponent(this.file.senderName || 'Sender')}`,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/octet-stream',
                    'Content-Length': buffer.length,
                    'X-File-Id': this.file.id || this.id,
                    'X-Chunk-Index': chunkIndex,
                    'X-Total-Chunks': totalChunks,
                    'X-File-Name': encodeURIComponent(this.file.name),
                    'X-File-Size': this.totalBytes
                }
            };

            const req = http.request(reqOptions, (res) => {
                let resData = '';
                res.on('data', d => resData += d);
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve();
                    } else {
                        reject(new Error(`Peer responded with HTTP ${res.statusCode}: ${resData}`));
                    }
                });
            });

            this._currentReq = req;

            req.on('error', (err) => {
                reject(new Error(`Connection to peer failed: ${err.message}`));
            });

            req.setTimeout(30000, () => {
                req.destroy(new Error('Chunk transfer timeout (30s)'));
            });

            req.write(buffer);
            req.end();
        });
    }

    _updateSpeed() {
        const now = Date.now();
        const duration = (now - this.lastSpeedCheckTime) / 1000;
        if (duration >= 0.5) {
            const bytesSinceLast = this.bytesTransferred - this.lastSpeedCheckBytes;
            this.speedBytesPerSec = bytesSinceLast / duration;
            this.lastSpeedCheckTime = now;
            this.lastSpeedCheckBytes = this.bytesTransferred;
        }
    }

    pause() {
        this._isPaused = true;
        this.status = 'paused';
        this.emit('status_change', this.getInfo());
    }

    resume() {
        this._isPaused = false;
        this.status = 'streaming';
        this.lastSpeedCheckTime = Date.now();
        this.lastSpeedCheckBytes = this.bytesTransferred;
        this.emit('status_change', this.getInfo());
    }

    cancel() {
        this._isCancelled = true;
        if (this._currentReq) {
            try { this._currentReq.destroy(); } catch (e) {}
        }
        this.status = 'cancelled';
        this.emit('status_change', this.getInfo());
    }

    getInfo() {
        const percent = this.totalBytes > 0 ? Math.min(100, Math.round((this.bytesTransferred / this.totalBytes) * 1000) / 10) : 0;
        const speedMBs = Math.round((this.speedBytesPerSec / (1024 * 1024)) * 10) / 10;
        const bytesRemaining = Math.max(0, this.totalBytes - this.bytesTransferred);
        const etaSeconds = this.speedBytesPerSec > 0 ? Math.round(bytesRemaining / this.speedBytesPerSec) : 0;

        return {
            id: this.id,
            fileName: this.file.name,
            fileSize: this.totalBytes,
            targetPeer: {
                id: this.targetPeer.id,
                name: this.targetPeer.name,
                ip: this.targetPeer.ip,
                avatar: this.targetPeer.avatar
            },
            status: this.status,
            bytesTransferred: this.bytesTransferred,
            percent,
            speedMBs,
            etaSeconds,
            errorMessage: this.errorMessage
        };
    }
}

/**
 * Worker Pool Engine
 * Allocates and manages concurrent transfer workers for single or multi-device broadcasts.
 */
class TransferWorkerPool extends EventEmitter {
    constructor({ maxConcurrentWorkers = 6 } = {}) {
        super();
        this.maxConcurrentWorkers = maxConcurrentWorkers;
        this.workers = new Map(); // workerId -> TransferWorker
    }

    /**
     * Dispatch a file to one or multiple peers concurrently
     */
    dispatchTransfer({ file, targetPeers, senderName = 'Device' }) {
        const assignedWorkers = [];

        for (const peer of targetPeers) {
            const workerId = `worker_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
            const worker = new TransferWorker({
                id: workerId,
                file: {
                    ...file,
                    id: file.id || `f_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
                    senderName
                },
                targetPeer: peer
            });

            this.workers.set(workerId, worker);

            worker.on('progress', (info) => this.emit('worker_progress', info));
            worker.on('status_change', (info) => this.emit('worker_status', info));
            worker.on('error', (err) => this.emit('worker_error', err));

            // Start worker stream immediately (zero delay)
            worker.start();
            assignedWorkers.push(worker);
        }

        return assignedWorkers.map(w => w.getInfo());
    }

    pauseWorker(workerId) {
        const w = this.workers.get(workerId);
        if (w) w.pause();
    }

    resumeWorker(workerId) {
        const w = this.workers.get(workerId);
        if (w) w.resume();
    }

    cancelWorker(workerId) {
        const w = this.workers.get(workerId);
        if (w) {
            w.cancel();
            this.workers.delete(workerId);
        }
    }

    getAllWorkers() {
        return Array.from(this.workers.values()).map(w => w.getInfo());
    }
}

module.exports = {
    TransferWorker,
    TransferWorkerPool
};
