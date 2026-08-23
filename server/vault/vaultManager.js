const fs = require('fs');
const path = require('path');
const os = require('os');
const { EventEmitter } = require('events');
const { computeFileHash } = require('../transfer/checksum');

const VAULT_DIR = path.join(process.cwd(), '.hyperdrop_vault');
const VAULT_DATA_FILE = path.join(VAULT_DIR, 'vault_index.json');

class VaultManager extends EventEmitter {
    constructor() {
        super();
        this.vaultDir = VAULT_DIR;
        this.indexFile = VAULT_DATA_FILE;
        this.files = [];
        this.activeUploads = new Map(); // fileId -> uploadData
        this.cancelledUploadIds = new Set();
        this._initStorage();
    }

    _initStorage() {
        if (!fs.existsSync(this.vaultDir)) {
            fs.mkdirSync(this.vaultDir, { recursive: true });
        }
        if (fs.existsSync(this.indexFile)) {
            try {
                this.files = JSON.parse(fs.readFileSync(this.indexFile, 'utf8'));
            } catch (e) {
                this.files = [];
            }
        } else {
            this.files = [];
            this._saveIndex();
        }
    }

    _saveIndex() {
        try {
            fs.writeFileSync(this.indexFile, JSON.stringify(this.files, null, 2), 'utf8');
        } catch (err) {
            console.error('[Vault] Error saving vault index:', err.message);
        }
    }

    categorizeFile(fileName) {
        const ext = path.extname(fileName).toLowerCase().replace('.', '');
        const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico', 'heic', 'heif', 'avif', 'tiff', 'tif', 'raw', 'cr2', 'nef', 'dng'];
        const videoExts = ['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', '3gp', 'm4v', 'ts', 'mts', 'vob', 'ogv'];
        const audioExts = ['mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac', 'wma', 'opus', 'aiff', 'alac', 'mid', 'midi'];
        const docExts = ['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'md', 'epub', 'mobi', 'pages', 'numbers', 'key'];
        const archiveExts = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'iso', 'xz', 'apk', 'dmg', 'pkg', 'deb', 'rpm', 'exe', 'msi'];
        const codeExts = ['js', 'ts', 'py', 'html', 'css', 'json', 'cpp', 'c', 'h', 'java', 'rs', 'go', 'php', 'dart', 'sh', 'bat', 'ps1', 'sql', 'xml', 'yaml', 'yml'];

        if (imageExts.includes(ext)) return 'image';
        if (videoExts.includes(ext)) return 'video';
        if (audioExts.includes(ext)) return 'audio';
        if (docExts.includes(ext)) return 'document';
        if (archiveExts.includes(ext)) return 'archive';
        if (codeExts.includes(ext)) return 'code';
        return 'other';
    }

    async handleChunk({ fileId, fileName, fileSize, chunkIndex, totalChunks, startByte = 0, senderId, senderName, targetPeerId, targetPeerName, chunkBuffer }) {
        if (this.cancelledUploadIds.has(fileId)) {
            return { status: 'cancelled' };
        }

        if (!this.activeUploads.has(fileId)) {
            const cleanName = path.basename(fileName).replace(/[^a-zA-Z0-9._-]/g, '_');
            const finalFileName = `${Date.now()}_${cleanName}`;
            const finalFilePath = path.join(this.vaultDir, finalFileName);
            
            // Open target file directly with read/write access
            let fd = null;
            try {
                fd = fs.openSync(finalFilePath, 'w+');
            } catch (err) {
                console.error('[Vault] Error creating target file:', err);
                throw err;
            }

            this.activeUploads.set(fileId, {
                fileId,
                fileName,
                vaultFileName: finalFileName,
                finalFilePath,
                fd,
                fileSize: Number(fileSize),
                totalChunks: Number(totalChunks),
                chunksReceived: new Set(),
                bytesReceived: 0,
                senderId: senderId || null,
                senderName: senderName || 'Peer',
                targetPeerId: targetPeerId || null,
                targetPeerName: targetPeerName || 'All Devices',
                startTime: Date.now(),
                lastTime: Date.now(),
                lastBytes: 0,
                speedMBs: 0.0,
                isCancelled: false
            });
        }

        const upload = this.activeUploads.get(fileId);
        if (!upload || upload.isCancelled || this.cancelledUploadIds.has(fileId)) {
            return { status: 'cancelled' };
        }

        // Direct seek and write at byte offset (100% memory efficient & zero temp files)
        const writeOffset = Number(startByte);
        try {
            fs.writeSync(upload.fd, chunkBuffer, 0, chunkBuffer.length, writeOffset);
        } catch (err) {
            console.error(`[Vault] Error writing chunk ${chunkIndex} at offset ${writeOffset}:`, err);
            throw err;
        }

        upload.chunksReceived.add(Number(chunkIndex));
        upload.bytesReceived += chunkBuffer.length;

        // Speed & ETA calculations
        const now = Date.now();
        const duration = (now - upload.lastTime) / 1000;
        if (duration >= 0.3) {
            const bytesSince = upload.bytesReceived - upload.lastBytes;
            upload.speedMBs = Math.round((bytesSince / (1024 * 1024) / duration) * 10) / 10;
            upload.lastTime = now;
            upload.lastBytes = upload.bytesReceived;
        }

        const remainingBytes = Math.max(0, upload.fileSize - upload.bytesReceived);
        const etaSeconds = upload.speedMBs > 0 ? Math.round(remainingBytes / (upload.speedMBs * 1024 * 1024)) : 0;
        const progressPercent = Math.min(100, Math.round((upload.bytesReceived / upload.fileSize) * 100));

        // Emit real-time progress specifically tagged for target device
        const progressPayload = {
            fileId,
            fileName: upload.fileName,
            fileSize: upload.fileSize,
            bytesTransferred: upload.bytesReceived,
            percent: progressPercent,
            speedMBs: upload.speedMBs,
            etaSeconds,
            senderId: upload.senderId,
            senderName: upload.senderName,
            targetPeerId: upload.targetPeerId,
            targetPeerName: upload.targetPeerName,
            status: 'receiving'
        };

        this.emit('upload_progress', progressPayload);

        // Check if all chunks received
        if (upload.chunksReceived.size >= upload.totalChunks) {
            return await this._finalizeFile(fileId);
        }

        return { status: 'receiving', progressPercent };
    }

    async _finalizeFile(fileId) {
        const upload = this.activeUploads.get(fileId);
        if (!upload || upload.isCancelled) return { status: 'cancelled' };
        if (upload.isFinalizing) return { status: 'finalizing' };
        upload.isFinalizing = true;

        // Close file descriptor cleanly
        try {
            if (upload.fd !== null) {
                fs.closeSync(upload.fd);
                upload.fd = null;
            }
        } catch (e) {}

        const finalFilePath = upload.finalFilePath;
        const hash = await computeFileHash(finalFilePath);
        const stats = fs.statSync(finalFilePath);
        const durationSec = ((Date.now() - upload.startTime) / 1000).toFixed(1);
        const avgSpeedMBs = (upload.fileSize / (1024 * 1024) / Math.max(0.1, durationSec)).toFixed(1);

        const vaultItem = {
            id: fileId,
            originalName: upload.fileName,
            vaultFileName: upload.vaultFileName,
            path: finalFilePath,
            size: stats.size,
            category: this.categorizeFile(upload.fileName),
            senderId: upload.senderId,
            senderName: upload.senderName,
            targetPeerId: upload.targetPeerId,
            targetPeerName: upload.targetPeerName,
            hash,
            durationSec,
            avgSpeedMBs,
            receivedAt: new Date().toISOString(),
            isExported: false,
            exportedPaths: []
        };

        this.files.unshift(vaultItem);
        this._saveIndex();
        this.activeUploads.delete(fileId);

        this.emit('file_received', vaultItem);
        return { status: 'completed', item: vaultItem };
    }

    getUploadStatus(fileId) {
        const upload = this.activeUploads.get(fileId);
        if (!upload) {
            // Check if already completed in files index
            const completed = this.files.find(f => f.id === fileId);
            if (completed) {
                return { isComplete: true, completedChunks: [], bytesReceived: completed.size, totalSize: completed.size };
            }
            return { isComplete: false, completedChunks: [], bytesReceived: 0, totalSize: 0 };
        }

        return {
            isComplete: false,
            fileId: upload.fileId,
            fileName: upload.fileName,
            fileSize: upload.fileSize,
            totalChunks: upload.totalChunks,
            completedChunks: Array.from(upload.chunksReceived),
            bytesReceived: upload.bytesReceived,
            nextChunkIndex: upload.chunksReceived.size
        };
    }

    cancelUpload(fileId) {
        this.cancelledUploadIds.add(fileId);
        const upload = this.activeUploads.get(fileId);
        if (upload) {
            upload.isCancelled = true;
            try {
                if (upload.fd !== null) {
                    fs.closeSync(upload.fd);
                    upload.fd = null;
                }
                if (fs.existsSync(upload.finalFilePath)) {
                    fs.unlinkSync(upload.finalFilePath);
                }
            } catch (e) {}
            this.activeUploads.delete(fileId);
        }
        this.emit('upload_cancelled', { fileId });
        return true;
    }

    getVaultItems({ category, search, peerId } = {}) {
        let list = [...this.files];
        if (category && category !== 'all') {
            list = list.filter(item => item.category === category);
        }
        if (search) {
            const query = search.toLowerCase();
            list = list.filter(item => item.originalName.toLowerCase().includes(query) || (item.senderName && item.senderName.toLowerCase().includes(query)));
        }
        return list;
    }

    getVaultItemById(id) {
        return this.files.find(item => item.id === id);
    }

    getVaultStats() {
        const totalFiles = this.files.length;
        const totalBytes = this.files.reduce((acc, f) => acc + (f.size || 0), 0);
        const categoriesCount = {};
        for (const f of this.files) {
            categoriesCount[f.category] = (categoriesCount[f.category] || 0) + 1;
        }
        return {
            totalFiles,
            totalBytes,
            categoriesCount
        };
    }

    deleteVaultItem(id) {
        const index = this.files.findIndex(item => item.id === id);
        if (index !== -1) {
            const item = this.files[index];
            if (fs.existsSync(item.path)) {
                try { fs.unlinkSync(item.path); } catch (e) {}
            }
            this.files.splice(index, 1);
            this._saveIndex();
            this.emit('file_deleted', id);
            return true;
        }
        return false;
    }

    addClipboardItem(item) {
        if (!this.clipboardHistory) this.clipboardHistory = [];
        this.clipboardHistory.unshift(item);
        if (this.clipboardHistory.length > 50) {
            this.clipboardHistory.pop();
        }
        return item;
    }

    getClipboardHistory() {
        return this.clipboardHistory || [];
    }

    clearClipboardHistory() {
        this.clipboardHistory = [];
    }

    clearVault() {
        for (const item of this.files) {
            if (fs.existsSync(item.path)) {
                try { fs.unlinkSync(item.path); } catch (e) {}
            }
        }
        this.files = [];
        this._saveIndex();
        this.emit('vault_cleared');
    }
}

module.exports = new VaultManager();
