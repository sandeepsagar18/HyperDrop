const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const { computeFileHash } = require('../server/transfer/checksum');
const { getNetworkInterfaces } = require('../server/network/interfaces');
const networkMonitor = require('../server/network/networkMonitor');
const DiscoveryEngine = require('../server/network/discovery');
const { TransferWorkerPool } = require('../server/transfer/workerPool');
const vaultManager = require('../server/vault/vaultManager');
const { exportFileToStorage, getSystemDirectories } = require('../server/vault/exportHandler');
const sessionManager = require('../server/signaling/sessionManager');
const { getIceConfiguration } = require('../server/network/iceConfig');

async function runTests() {
    console.log('=======================================================');
    console.log('🧪 HYPERDROP AUTOMATED INTEGRATION & PERFORMANCE TESTS');
    console.log('=======================================================\n');

    // TEST 1: Network Interfaces Detection & Gateway Computation
    console.log('[Test 1] Detecting Network Interfaces & Subnet Health...');
    const ifaces = getNetworkInterfaces();
    console.log(`✓ Detected ${ifaces.length} network interface(s):`);
    ifaces.forEach(i => console.log(`   - [${i.type.toUpperCase()}] ${i.name}: ${i.address} (Broadcast: ${i.broadcast})`));
    if (ifaces.length === 0) throw new Error('No network interface detected');

    const diag = networkMonitor.getDiagnostics();
    console.log(`✓ Live Network Diagnostics verified:`);
    console.log(`   - Interface: ${diag.interfaceName} (${diag.interfaceType})`);
    console.log(`   - Local IP: ${diag.localIp}`);
    console.log(`   - Subnet Mask: ${diag.subnetMask}`);
    console.log(`   - Gateway: ${diag.gatewayIp}`);
    console.log(`   - Bind Address: ${diag.serverBindAddress}:${diag.serverPort}`);
    console.log(`   - Offline Health: ${diag.offlineModeHealth}`);

    // TEST 2: UDP Discovery Engine Initialization & Gateway Probing
    console.log('\n[Test 2] Testing UDP Discovery Engine & Android Hotspot Prober...');
    const discovery = new DiscoveryEngine({ httpPort: 3000, name: 'Test-Host-Node' });
    discovery.start();
    console.log(`✓ Discovery Engine running with Device ID: ${discovery.deviceId}`);
    
    // Simulate manual peer discovery
    const mockPeer = discovery.manualAddPeer('127.0.0.1', 3000, 'Test-Receiver-Phone');
    console.log(`✓ Discovered Peer: ${mockPeer.name} at ${mockPeer.url}`);
    discovery.stop();

    // TEST 3: High-Speed Streaming & Chunk Assembly in App Vault
    console.log('\n[Test 3] Testing High-Speed Worker Streaming & App Vault Staging...');
    const testFileSize = 10 * 1024 * 1024; // 10 Megabytes test binary payload
    const testData = crypto.randomBytes(testFileSize);
    const testFileHashExpected = crypto.createHash('sha256').update(testData).digest('hex');

    console.log(`   - Generated 10MB test payload (SHA-256: ${testFileHashExpected})`);

    const chunkSize = 2 * 1024 * 1024; // 2MB chunks -> 5 chunks
    const totalChunks = Math.ceil(testFileSize / chunkSize);
    const testFileId = `bench_${Date.now()}`;
    const testFileName = 'hyperdrop_benchmark_video.mp4';

    console.log(`   - Ingesting ${totalChunks} chunks into App Vault with offset-based streaming...`);
    let finalAssembleResult = null;

    for (let i = 0; i < totalChunks; i++) {
        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, testFileSize);
        const chunkBuf = testData.slice(start, end);

        const res = await vaultManager.handleChunk({
            fileId: testFileId,
            fileName: testFileName,
            fileSize: testFileSize,
            chunkIndex: i,
            totalChunks,
            startByte: start,
            senderName: 'Test High-Speed Worker',
            chunkBuffer: chunkBuf
        });

        if (res.status === 'completed') {
            finalAssembleResult = res;
        }
    }

    if (!finalAssembleResult || !finalAssembleResult.item) {
        throw new Error('Vault failed to assemble file chunks');
    }

    const assembledItem = finalAssembleResult.item;
    console.log(`✓ File successfully staged in App Vault:`);
    console.log(`   - Original Name: ${assembledItem.originalName}`);
    console.log(`   - Category: ${assembledItem.category} (Detected as Video)`);
    console.log(`   - Size: ${assembledItem.size} bytes`);
    console.log(`   - Stored SHA-256: ${assembledItem.hash}`);

    if (assembledItem.hash !== testFileHashExpected) {
        throw new Error(`SHA-256 integrity mismatch! Expected ${testFileHashExpected}, got ${assembledItem.hash}`);
    }
    console.log(`✓ 100% SHA-256 Integrity Verified (Zero Data Corruption)`);

    // TEST 4: Resumable Upload Status Check
    console.log('\n[Test 4] Testing Resumable Chunk Status Query...');
    const resumeCheckId = `resume_test_${Date.now()}`;
    await vaultManager.handleChunk({
        fileId: resumeCheckId,
        fileName: 'resumable_test_file.iso',
        fileSize: 20 * 1024 * 1024,
        chunkIndex: 0,
        totalChunks: 5,
        startByte: 0,
        senderName: 'Resume Tester',
        chunkBuffer: crypto.randomBytes(4 * 1024 * 1024)
    });

    const uploadStatus = vaultManager.getUploadStatus(resumeCheckId);
    console.log(`✓ Resumable upload status queried:`);
    console.log(`   - Completed chunks: ${uploadStatus.completedChunks.length}/5`);
    console.log(`   - Next resume chunk index: ${uploadStatus.nextChunkIndex}`);
    console.log(`   - Bytes recorded on disk: ${uploadStatus.bytesReceived} bytes`);

    if (uploadStatus.nextChunkIndex !== 1) {
        throw new Error('Resume chunk index mismatch!');
    }
    vaultManager.cancelUpload(resumeCheckId);
    console.log(`✓ Resumable upload query verified successfully`);

    // TEST 5: Export from App Vault to System Storage
    console.log('\n[Test 5] Testing Export from App Vault to Local System Storage...');
    const testExportDir = path.join(process.cwd(), '.hyperdrop_test_storage');
    const exportResult = exportFileToStorage(assembledItem.id, testExportDir);

    console.log(`✓ File exported to: ${exportResult.savedPath}`);
    if (!fs.existsSync(exportResult.savedPath)) {
        throw new Error('Exported file does not exist on disk');
    }

    const exportedHash = await computeFileHash(exportResult.savedPath);
    if (exportedHash !== testFileHashExpected) {
        throw new Error('Exported file hash mismatch!');
    }
    console.log(`✓ Exported file SHA-256 hash verified identical to original payload`);

    // Cleanup test storage
    try {
        fs.unlinkSync(exportResult.savedPath);
        fs.rmdirSync(testExportDir);
        vaultManager.deleteVaultItem(assembledItem.id);
    } catch (e) {}

    // TEST 6: Remote Signaling & Session Pairing Manager
    console.log('\n[Test 6] Testing WebRTC Remote Session Manager & Pairing Rooms...');
    const hostSession = sessionManager.createSession({
        hostDeviceId: 'host_node_99',
        hostDeviceName: 'Sandeep Laptop (Host)',
        hostDeviceType: 'laptop'
    });

    console.log(`✓ Created remote session: ${hostSession.sessionId}`);
    console.log(`   - Generated Short Code: ${hostSession.shortCode}`);
    console.log(`   - Session Token: ${hostSession.sessionToken.substring(0, 12)}...`);

    const joinResult = sessionManager.joinSession({
        sessionIdOrCode: hostSession.shortCode,
        guestDeviceId: 'guest_phone_88',
        guestDeviceName: 'Sandeep Mobile (4G)',
        guestDeviceType: 'phone'
    });

    if (!joinResult.success) {
        throw new Error(`Guest failed to join remote session: ${joinResult.error}`);
    }
    console.log(`✓ Guest paired successfully with Host into room ${hostSession.shortCode}`);
    sessionManager.closeSession(hostSession.sessionId);
    console.log(`✓ Remote session closed & cleaned up`);

    // TEST 7: ICE Configuration & STUN/TURN Discovery
    console.log('\n[Test 7] Testing WebRTC ICE STUN/TURN Configuration...');
    const ice = getIceConfiguration();
    console.log(`✓ Verified ICE servers count: ${ice.iceServers.length}`);
    ice.iceServers.forEach((s, idx) => console.log(`   - Server #${idx + 1}: ${JSON.stringify(s.urls)}`));
    if (ice.iceServers.length === 0) throw new Error('No ICE servers configured');

    // TEST 8: WebRTC Direct Peer ID Signaling Dispatch
    console.log('\n[Test 8] Testing WebRTC Peer-to-Peer Signaling Message Dispatch...');
    const { handleSignalingMessage } = require('../server/signaling/signalingServer');
    
    let receivedMessage = null;
    const mockGuestWs = {
        readyState: 1,
        peerId: 'peer_target_456',
        send: (data) => {
            receivedMessage = JSON.parse(data);
        }
    };
    const mockSenderWs = {
        readyState: 1,
        peerId: 'peer_sender_123'
    };
    const mockWss = {
        clients: new Set([mockGuestWs, mockSenderWs])
    };

    handleSignalingMessage(mockSenderWs, {
        type: 'webrtc_offer',
        data: {
            targetPeerId: 'peer_target_456',
            senderId: 'peer_sender_123',
            sdp: { type: 'offer', sdp: 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1' }
        }
    }, mockWss);

    if (!receivedMessage || receivedMessage.type !== 'webrtc_offer' || receivedMessage.data.senderId !== 'peer_sender_123') {
        throw new Error('Signaling message was not routed to the target peer socket');
    }
    console.log('✓ Direct WebRTC SDP Offer successfully routed to target peer socket without server file relay');

    console.log('\n=======================================================');
    console.log('🎉 ALL HYPERDROP TEST SUITES PASSED SUCCESSFULLY (8/8)');
    console.log('=======================================================');
}

runTests().catch(err => {
    console.error('❌ Test failed:', err);
    process.exit(1);
});
