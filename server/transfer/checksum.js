const crypto = require('crypto');
const fs = require('fs');

/**
 * Computes SHA-256 hash of a file as a stream (memory efficient for 100GB+ files)
 */
function computeFileHash(filePath) {
    return new Promise((resolve, reject) => {
        const hash = crypto.createHash('sha256');
        const stream = fs.createReadStream(filePath);

        stream.on('data', (chunk) => hash.update(chunk));
        stream.on('end', () => resolve(hash.digest('hex')));
        stream.on('error', (err) => reject(err));
    });
}

/**
 * Computes SHA-256 of an in-memory buffer
 */
function computeBufferHash(buffer) {
    return crypto.createHash('sha256').update(buffer).digest('hex');
}

module.exports = {
    computeFileHash,
    computeBufferHash
};
