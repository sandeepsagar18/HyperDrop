const fs = require('fs');
const path = require('path');
const os = require('os');
const vaultManager = require('./vaultManager');

/**
 * Returns default system directories for storage export
 */
function getSystemDirectories() {
    const homedir = os.homedir();
    return {
        downloads: path.join(homedir, 'Downloads'),
        documents: path.join(homedir, 'Documents'),
        desktop: path.join(homedir, 'Desktop'),
        pictures: path.join(homedir, 'Pictures'),
        videos: path.join(homedir, 'Videos'),
        music: path.join(homedir, 'Music')
    };
}

/**
 * Export a single file from the vault to a system target directory
 */
function exportFileToStorage(vaultFileId, targetDirectory = null) {
    const item = vaultManager.getVaultItemById(vaultFileId);
    if (!item) {
        throw new Error('File not found in Vault');
    }

    if (!fs.existsSync(item.path)) {
        throw new Error('Vault source file is missing');
    }

    const defaultDirs = getSystemDirectories();
    const destFolder = targetDirectory || defaultDirs.downloads;

    if (!fs.existsSync(destFolder)) {
        fs.mkdirSync(destFolder, { recursive: true });
    }

    // Determine unique destination file name
    let destName = item.originalName;
    let destPath = path.join(destFolder, destName);
    let counter = 1;
    const parsed = path.parse(item.originalName);

    while (fs.existsSync(destPath)) {
        destName = `${parsed.name}_(${counter})${parsed.ext}`;
        destPath = path.join(destFolder, destName);
        counter++;
    }

    // Copy file
    fs.copyFileSync(item.path, destPath);

    // Update vault metadata
    item.isExported = true;
    if (!item.exportedPaths) item.exportedPaths = [];
    item.exportedPaths.push(destPath);
    vaultManager._saveIndex();

    return {
        success: true,
        originalName: item.originalName,
        savedPath: destPath,
        directory: destFolder
    };
}

/**
 * Batch export multiple vault files
 */
function batchExportToStorage(vaultFileIds, targetDirectory = null) {
    const results = [];
    for (const id of vaultFileIds) {
        try {
            const res = exportFileToStorage(id, targetDirectory);
            results.push(res);
        } catch (err) {
            results.push({
                success: false,
                id,
                error: err.message
            });
        }
    }
    return results;
}

module.exports = {
    getSystemDirectories,
    exportFileToStorage,
    batchExportToStorage
};
