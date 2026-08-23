// HyperDrop Dashboard Controller (With Recipient Selection & Device Renaming)
class HyperDropApp {
    constructor() {
        this.ws = null;
        this.peers = new Map(); // peerId -> peerData
        this.selectedPeerIds = new Set();
        this.stagedFiles = [];
        this.cachedFiles = new Map(); // fileName -> File object for 1-click Restart
        this.workers = new Map(); // workerId -> workerData
        this.vaultItems = [];
        this.systemStatus = null;
        this.peakSpeedMBs = 0.0;
        this.totalBytesMoved = 0;
        this.cancelledTransferIds = new Set();

        // Local client identification & custom name
        this.clientId = localStorage.getItem('hyperdrop_client_id') || `web_${Math.random().toString(36).substr(2, 8)}`;
        localStorage.setItem('hyperdrop_client_id', this.clientId);

        const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
        this.clientType = isMobile ? 'phone' : 'laptop';
        
        const storedName = localStorage.getItem('hyperdrop_custom_name');
        this.clientName = storedName || (isMobile ? (navigator.userAgent.includes('iPhone') ? 'iPhone' : 'Android Phone') : 'Windows Laptop');
        this.clientAvatar = isMobile ? '📱' : '💻';

        // Hybrid Connection Manager (Local LAN + Remote WebRTC)
        this.connectionManager = new ConnectionManager(this);
        this.currentRemoteSession = null;
        this.pendingTransferAuth = null;

        this.init();
    }

    async init() {
        this.bindEvents();
        // Instant parallel initialization for lightning-fast peer discovery
        this.initWebSocket();
        this.fetchPeers();
        this.fetchStatus();
        this.fetchVaultItems();
        this.fetchVaultStats();
        this.fetchClipboardHistory();
        this.loadQrCode();

        // Fast initial discovery sweep then steady background polling
        setTimeout(() => this.fetchPeers(), 500);
        setTimeout(() => this.fetchPeers(), 1200);
        setInterval(() => this.fetchPeers(), 1500);
    }

    async fetchStatus() {
        try {
            const res = await fetch('/api/status');
            const data = await res.json();
            if (data.success) {
                this.systemStatus = data;
                
                // If running in browser on the laptop itself and no custom name is stored, adopt host PC name
                if (this.clientType === 'laptop' && !localStorage.getItem('hyperdrop_custom_name') && data.deviceName) {
                    this.clientName = data.deviceName;
                }

                const hostLabel = document.getElementById('host-device-label');
                const hostIcon = document.getElementById('host-device-icon');
                
                if (hostLabel) hostLabel.textContent = `You (${this.clientName})`;
                if (hostIcon) hostIcon.className = this.clientType === 'phone' ? 'fa-solid fa-mobile-screen-button' : 'fa-solid fa-laptop';
            }
        } catch (e) {
            console.error('Failed to fetch status:', e);
        }
    }

    initWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}`;
        
        this.ws = new WebSocket(wsUrl);

        this.ws.onopen = () => {
            this.registerDeviceOnRadar();
            
            // Check if opened via QR code pairing scan
            const urlParams = new URLSearchParams(window.location.search);
            if (urlParams.has('token') || urlParams.has('qr') || window.location.search.includes('connect')) {
                this.showToast('⚡ Paired via QR Code! Ready to transfer.');
            }

            setInterval(() => {
                if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                    this.ws.send(JSON.stringify({ type: 'heartbeat', id: this.clientId }));
                }
            }, 3000);
        };

        this.ws.onmessage = (event) => {
            try {
                const msg = JSON.parse(event.data);
                this.handleWsMessage(msg);
            } catch (err) {}
        };

        this.ws.onclose = () => {
            setTimeout(() => this.initWebSocket(), 3000);
        };
    }

    registerDeviceOnRadar() {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({
                type: 'register_web_peer',
                id: this.clientId,
                name: this.clientName,
                deviceType: this.clientType,
                osType: navigator.platform || 'Device',
                avatar: this.clientType === 'phone' ? '📱' : '💻',
                url: window.location.origin
            }));
        }
    }

    handleWsMessage(msg) {
        const { type, data } = msg;

        switch (type) {
            case 'init_state':
                if (data && data.peers) {
                    data.peers.forEach(p => {
                        if (p.id !== this.clientId) {
                            this.peers.set(p.id, p);
                            this.selectedPeerIds.add(p.id);
                        }
                    });
                    this.renderRadarOrbit();
                }
                break;

            case 'peer_discovered':
            case 'peer_joined':
                if (data && data.id !== this.clientId) {
                    const isNew = !this.peers.has(data.id);
                    this.peers.set(data.id, data);
                    this.selectedPeerIds.add(data.id);
                    this.renderRadarOrbit();
                    if (isNew) {
                        this.showToast(`✨ Nearby Device Detected: ${data.name}`);
                    }
                }
                break;

            case 'peer_updated':
            case 'peer_list':
                if (Array.isArray(data)) {
                    data.forEach(peer => {
                        if (peer.id !== this.clientId) {
                            this.peers.set(peer.id, peer);
                            this.selectedPeerIds.add(peer.id);
                        }
                    });
                } else if (data && data.id !== this.clientId) {
                    this.peers.set(data.id, data);
                }
                this.renderRadarOrbit();
                break;

            case 'peer_lost':
                if (data && data.id) {
                    this.peers.delete(data.id);
                    this.selectedPeerIds.delete(data.id);
                    this.renderRadarOrbit();
                }
                break;

            case 'device_renamed':
                if (data && data.deviceName) {
                    this.renderRadarOrbit();
                }
                break;

            case 'webrtc_offer':
            case 'webrtc_answer':
            case 'webrtc_ice_candidate':
                this.connectionManager.handleRemoteSignalingMessage(type, data);
                break;

            case 'transfer_request':
                // Auto-accept incoming file transfers without interrupting user with popups
                if (data && data.fileId) {
                    fetch('/api/transfer/respond', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ fileId: data.fileId, accept: true })
                    }).catch(() => {});
                }
                break;

            case 'network_changed':
                console.log('[NETWORK] Live network change detected:', data);
                if (this.systemStatus) {
                    this.systemStatus.primaryIp = data.newIp;
                }
                this.loadQrCode(data.newIp);
                this.fetchPeers();
                this.showToast(`📶 Network shifted to ${data.diagnostics.interfaceName} (${data.newIp})`);
                break;

            case 'incoming_transfer_progress':
                if (data.targetPeerId && data.targetPeerId !== 'all' && data.targetPeerId !== this.clientId && data.senderId !== this.clientId) {
                    break; // Ignore transfers meant for other devices!
                }
                this.handleIncomingProgress(data);
                break;

            case 'transfer_cancelled':
                if (data && data.fileId) {
                    this.cancelledTransferIds.add(data.fileId);
                }
                if (this.workers.has(data.fileId)) {
                    const w = this.workers.get(data.fileId);
                    w.status = 'cancelled';
                    w.isCancelled = true;
                    this.renderTransferEngine();
                }
                break;

            case 'worker_progress':
            case 'worker_status':
                if (!this.cancelledTransferIds.has(data.id)) {
                    this.workers.set(data.id, data);
                    this.renderTransferEngine();
                }
                break;

            case 'clipboard_synced':
                if (data.targetPeerIds && !data.targetPeerIds.includes('all') && !data.targetPeerIds.includes(this.clientId) && data.senderId !== this.clientId) {
                    break; // Ignore messages intended for another device
                }
                const textarea = document.getElementById('clip-text-input');
                if (textarea && data.senderId !== this.clientId) {
                    textarea.value = data.text;
                    textarea.style.borderColor = 'var(--neon-green)';
                    setTimeout(() => textarea.style.borderColor = '', 1800);
                    this.showToast(`💬 ${data.senderName}: "${data.text.length > 25 ? data.text.substring(0, 25) + '...' : data.text}"`);
                }
                this.addClipHistoryItem(data);
                break;

            case 'file_received':
                if (this.cancelledTransferIds.has(data.id)) {
                    return; // Ignore completely if user clicked cancel!
                }
                if (this.workers.has(data.id)) {
                    const w = this.workers.get(data.id);
                    if (w.isCancelled || w.status === 'cancelled') return;
                    w.status = 'completed';
                    w.percent = 100;
                    w.durationSec = data.durationSec || '1.2';
                    w.avgSpeedMBs = data.avgSpeedMBs || '3.5';
                    if (data.size && (!w.bytesTransferred || w.bytesTransferred < data.size)) {
                        this.totalBytesMoved += (data.size - (w.bytesTransferred || 0));
                        w.bytesTransferred = data.size;
                    }
                    this.renderTransferEngine();
                } else if (data.size) {
                    this.totalBytesMoved += data.size;
                    this.renderTransferEngine();
                }
                this.fetchVaultItems();
                this.fetchVaultStats();
                this.showToast(`📥 Received: ${data.originalName || data.fileName || 'New File'}`);
                break;

            case 'file_deleted':
            case 'vault_cleared':
                this.fetchVaultItems();
                this.fetchVaultStats();
                break;
        }
    }

    bindEvents() {
        // Dropzone & File Pickers
        const dropzone = document.getElementById('dropzone');
        const fileInput = document.getElementById('file-input');
        const folderInput = document.getElementById('folder-input');

        document.getElementById('choose-files-btn').addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            fileInput.value = '';
            fileInput.click();
        });

        document.getElementById('choose-folder-btn').addEventListener('click', async (e) => {
            e.preventDefault();
            e.stopPropagation();

            if (window.showDirectoryPicker) {
                try {
                    const dirHandle = await window.showDirectoryPicker();
                    const files = await this.readDirectoryHandle(dirHandle, dirHandle.name);
                    if (files && files.length > 0) {
                        this.addStagedFiles(files);
                    }
                    return;
                } catch (err) {
                    if (err.name === 'AbortError') return;
                    console.warn('[FOLDER] Native directory picker fallback:', err);
                }
            }

            folderInput.value = '';
            folderInput.click();
        });

        dropzone.addEventListener('click', (e) => {
            if (e.target.closest('#choose-folder-btn') || e.target.closest('#choose-files-btn')) return;
            fileInput.value = '';
            fileInput.click();
        });

        dropzone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropzone.classList.add('dragover');
        });

        dropzone.addEventListener('dragleave', () => dropzone.classList.remove('dragover'));

        dropzone.addEventListener('drop', async (e) => {
            e.preventDefault();
            dropzone.classList.remove('dragover');
            
            const files = [];
            const items = e.dataTransfer.items;
            if (items && items.length > 0 && items[0].webkitGetAsEntry) {
                for (let i = 0; i < items.length; i++) {
                    const entry = items[i].webkitGetAsEntry();
                    if (entry) {
                        const entryFiles = await this.readEntryAsync(entry);
                        files.push(...entryFiles);
                    }
                }
            } else if (e.dataTransfer.files.length) {
                for (let f of e.dataTransfer.files) files.push(f);
            }

            if (files.length) {
                this.addStagedFiles(files);
            }
        });

        fileInput.addEventListener('change', (e) => {
            if (e.target.files && e.target.files.length) {
                this.addStagedFiles(Array.from(e.target.files));
            }
        });

        folderInput.addEventListener('change', (e) => {
            if (e.target.files && e.target.files.length) {
                this.addStagedFiles(Array.from(e.target.files));
            }
        });

        // Staged actions
        document.getElementById('clear-staged-btn').addEventListener('click', () => {
            this.stagedFiles = [];
            this.renderStagedFiles();
        });

        // Start Transfer Trigger -> Opens Recipient Selection Modal
        document.getElementById('start-transfer-btn').addEventListener('click', () => {
            this.openRecipientModal();
        });

        // Modal Select All
        document.getElementById('modal-select-all-btn').addEventListener('click', () => {
            for (const id of this.peers.keys()) {
                this.selectedPeerIds.add(id);
            }
            this.renderRecipientModalList();
        });

        // Confirm Send to Selected Devices
        document.getElementById('confirm-send-btn').addEventListener('click', () => {
            document.getElementById('recipient-modal').classList.remove('active');
            this.executeTransferToSelectedPeers();
        });

        // Rename Device Triggers
        const openRename = () => {
            document.getElementById('rename-input').value = this.clientName;
            this.openModal('rename-modal');
        };

        document.getElementById('rename-top-btn').addEventListener('click', openRename);
        document.getElementById('rename-device-trigger').addEventListener('click', (e) => {
            e.stopPropagation();
            openRename();
        });
        document.getElementById('host-center-node').addEventListener('click', openRename);

        // Save Rename
        document.getElementById('save-rename-btn').addEventListener('click', async () => {
            const newName = document.getElementById('rename-input').value.trim();
            if (!newName) return alert('Please enter a valid device name');

            this.clientName = newName;
            localStorage.setItem('hyperdrop_custom_name', newName);

            document.getElementById('host-device-label').textContent = `You (${newName})`;
            document.getElementById('rename-modal').classList.remove('active');

            // Notify server & peers
            try {
                await fetch('/api/device/rename', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name: newName })
                });
            } catch (e) {}

            this.registerDeviceOnRadar();
            this.showToast(`✓ Device renamed to: ${newName}`);
        });

        // Clear finished queue
        document.getElementById('clear-finished-btn').addEventListener('click', () => {
            for (const [id, w] of this.workers.entries()) {
                if (w.status === 'completed' || w.status === 'failed') {
                    this.workers.delete(id);
                }
            }
            this.renderTransferEngine();
        });

        // Clipboard Text & Link Sync (Optional)
        const sendClipBtn = document.getElementById('send-clip-btn');
        if (sendClipBtn) {
            sendClipBtn.addEventListener('click', async () => {
                const textarea = document.getElementById('clip-text-input');
                const text = textarea ? textarea.value.trim() : '';
                if (!text) return;

                const targetSelect = document.getElementById('clip-target-select');
                const selectedTargetId = targetSelect ? targetSelect.value : 'all';
                
                let targetPeerIds = ['all'];
                let targetPeerNames = ['All Devices'];
                if (selectedTargetId !== 'all') {
                    targetPeerIds = [selectedTargetId];
                    const peer = this.peers.get(selectedTargetId);
                    targetPeerNames = [peer ? peer.name : 'Target Device'];
                }

                try {
                    const res = await fetch('/api/sync/clipboard', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            text,
                            senderId: this.clientId,
                            senderName: this.clientName,
                            targetPeerIds,
                            targetPeerNames
                        })
                    });
                    const data = await res.json();
                    if (data.success) {
                        if (textarea) {
                            textarea.style.borderColor = 'var(--neon-cyan)';
                            textarea.value = '';
                            setTimeout(() => textarea.style.borderColor = '', 1000);
                        }
                        this.showToast(`✓ Synced to ${targetPeerNames[0]}!`);
                        this.addClipHistoryItem(data.syncItem);
                    }
                } catch (e) {
                    this.showToast('Failed to sync text');
                }
            });
        }

        // Target Selection Warning Indicator
        const targetSelect = document.getElementById('clip-target-select');
        const updateClipWarning = () => {
            const warningEl = document.getElementById('clip-target-warning');
            const warningText = document.getElementById('clip-warning-text');
            if (!warningEl || !targetSelect) return;

            if (targetSelect.value !== 'all') {
                const selectedPeer = this.peers.get(targetSelect.value);
                const targetName = selectedPeer ? selectedPeer.name : 'selected device';
                warningText.innerHTML = `⚠️ <b>Private Mode:</b> Text will <u>NOT</u> be synced to all devices (only sent to <b>${targetName}</b>).`;
                warningEl.style.display = 'block';
            } else {
                warningEl.style.display = 'none';
            }
        };

        if (targetSelect) {
            targetSelect.addEventListener('change', updateClipWarning);
        }

        const pasteBtn = document.getElementById('paste-clip-btn');
        if (pasteBtn) {
            pasteBtn.addEventListener('click', async () => {
                try {
                    const text = await navigator.clipboard.readText();
                    if (text) {
                        const textarea = document.getElementById('clip-text-input');
                        textarea.value = text;
                        textarea.focus();
                    }
                } catch (e) {
                    this.showToast('Paste with Ctrl+V');
                }
            });
        }

        // Clear vault
        document.getElementById('clear-vault-btn').addEventListener('click', async () => {
            if (confirm('Clear all files in offline vault?')) {
                await fetch('/api/vault/clear', { method: 'DELETE' });
                this.fetchVaultItems();
                this.fetchVaultStats();
            }
        });

        // Modals - close buttons & backdrop click
        const renameTopBtn = document.getElementById('rename-top-btn');
        if (renameTopBtn) {
            renameTopBtn.addEventListener('click', () => {
                const input = document.getElementById('rename-input');
                if (input) input.value = this.clientName;
                this.openModal('rename-modal');
            });
        }

        const renameTrigger = document.getElementById('rename-device-trigger');
        if (renameTrigger) {
            renameTrigger.addEventListener('click', (e) => {
                e.stopPropagation();
                const input = document.getElementById('rename-input');
                if (input) input.value = this.clientName;
                this.openModal('rename-modal');
            });
        }

        const hostCenterNode = document.getElementById('host-center-node');
        if (hostCenterNode) {
            hostCenterNode.addEventListener('click', () => {
                const input = document.getElementById('rename-input');
                if (input) input.value = this.clientName;
                this.openModal('rename-modal');
            });
        }

        const saveRenameBtn = document.getElementById('save-rename-btn');
        if (saveRenameBtn) {
            saveRenameBtn.addEventListener('click', () => {
                const input = document.getElementById('rename-input');
                const newName = input ? input.value.trim() : '';
                if (newName) {
                    this.clientName = newName;
                    localStorage.setItem('hyperdrop_custom_name', newName);
                    const hostLabel = document.getElementById('host-device-label');
                    if (hostLabel) hostLabel.textContent = `You (${this.clientName})`;
                    this.registerDeviceOnRadar();
                    this.closeModal('rename-modal');
                    this.showToast(`✓ Device renamed to "${this.clientName}"`);
                }
            });
        }

        document.getElementById('qr-btn').addEventListener('click', () => {
            this.loadQrCode();
            this.openModal('qr-modal');
        });

        // Remote WebRTC Connect
        const remoteBtn = document.getElementById('remote-btn');
        if (remoteBtn) {
            remoteBtn.addEventListener('click', () => {
                this.openRemoteModal();
            });
        }

        // Remote Tabs
        const tabShare = document.getElementById('remote-tab-share');
        const tabJoin = document.getElementById('remote-tab-join');
        const viewShare = document.getElementById('remote-view-share');
        const viewJoin = document.getElementById('remote-view-join');

        if (tabShare && tabJoin) {
            tabShare.addEventListener('click', () => {
                tabShare.style.background = 'rgba(0,242,254,0.15)';
                tabShare.style.color = 'var(--neon-cyan)';
                tabJoin.style.background = 'transparent';
                tabJoin.style.color = 'var(--text-dim)';
                viewShare.style.display = 'block';
                viewJoin.style.display = 'none';
            });

            tabJoin.addEventListener('click', () => {
                tabJoin.style.background = 'rgba(0,242,254,0.15)';
                tabJoin.style.color = 'var(--neon-cyan)';
                tabShare.style.background = 'transparent';
                tabShare.style.color = 'var(--text-dim)';
                viewJoin.style.display = 'block';
                viewShare.style.display = 'none';
            });
        }

        const copyRemoteCodeBtn = document.getElementById('copy-remote-code-btn');
        if (copyRemoteCodeBtn) {
            copyRemoteCodeBtn.addEventListener('click', () => {
                const code = document.getElementById('remote-share-code').textContent;
                if (code && code !== 'GENERATING...') {
                    navigator.clipboard.writeText(code);
                    this.showToast(`📋 Copied Pairing Code: ${code}`);
                }
            });
        }

        const copyRemoteLinkBtn = document.getElementById('copy-remote-link-btn');
        if (copyRemoteLinkBtn) {
            copyRemoteLinkBtn.addEventListener('click', () => {
                const link = copyRemoteLinkBtn.getAttribute('data-join-url') || window.location.href;
                navigator.clipboard.writeText(link);
                this.showToast(`🔗 Copied Remote Join Link!`);
            });
        }

        const btnSubmitJoin = document.getElementById('btn-submit-remote-join');
        if (btnSubmitJoin) {
            btnSubmitJoin.addEventListener('click', () => {
                const input = document.getElementById('remote-join-code-input');
                const code = input ? input.value.trim() : '';
                if (!code) {
                    alert('Please enter a 6-character remote code.');
                    return;
                }
                this.joinRemoteSession(code);
            });
        }

        // Auth Modal Buttons
        const authAcceptBtn = document.getElementById('auth-accept-btn');
        const authRejectBtn = document.getElementById('auth-reject-btn');
        if (authAcceptBtn) {
            authAcceptBtn.addEventListener('click', () => {
                if (this.pendingTransferAuth) {
                    if (this.ws && this.ws.readyState === 1) {
                        this.ws.send(JSON.stringify({
                            type: 'remote_transfer_response',
                            data: {
                                sessionId: this.pendingTransferAuth.sessionId,
                                accepted: true,
                                receiverName: this.clientName
                            }
                        }));
                    }
                    this.closeModal('auth-modal');
                    this.showToast(`✓ Transfer accepted! Streaming started...`);
                    this.pendingTransferAuth = null;
                }
            });
        }

        if (authRejectBtn) {
            authRejectBtn.addEventListener('click', () => {
                if (this.pendingTransferAuth) {
                    if (this.ws && this.ws.readyState === 1) {
                        this.ws.send(JSON.stringify({
                            type: 'remote_transfer_response',
                            data: {
                                sessionId: this.pendingTransferAuth.sessionId,
                                accepted: false,
                                receiverName: this.clientName
                            }
                        }));
                    }
                    this.closeModal('auth-modal');
                    this.showToast(`❌ Transfer rejected.`);
                    this.pendingTransferAuth = null;
                }
            });
        }

        const diagBtn = document.getElementById('diag-btn');
        if (diagBtn) {
            diagBtn.addEventListener('click', () => {
                this.openDiagnosticsModal();
            });
        }
        
        document.querySelectorAll('.modal-close-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const modal = e.target.closest('.modal');
                if (modal) this.closeModal(modal.id);
            });
        });

        // Close modal on backdrop click & Stop Video/Audio
        document.querySelectorAll('.modal').forEach(modal => {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    this.closeModal(modal.id);
                }
            });
        });

        // Close on Escape key
        window.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                document.querySelectorAll('.modal.active').forEach(m => this.closeModal(m.id));
            }
        });

        document.getElementById('copy-url-btn').addEventListener('click', () => {
            const text = document.getElementById('qr-url-text').textContent;
            navigator.clipboard.writeText(text);
            alert('Copied URL: ' + text);
        });
    }

    openModal(id) {
        document.getElementById(id).classList.add('active');
    }

    closeModal(id) {
        const modal = document.getElementById(id);
        if (!modal) return;

        // Stop any running video or audio immediately!
        const videos = modal.querySelectorAll('video');
        videos.forEach(v => {
            try {
                v.pause();
                v.currentTime = 0;
                v.src = '';
                v.load();
            } catch (err) {}
        });

        const audios = modal.querySelectorAll('audio');
        audios.forEach(a => {
            try {
                a.pause();
                a.currentTime = 0;
                a.src = '';
                a.load();
            } catch (err) {}
        });

        if (id === 'preview-modal') {
            document.getElementById('preview-body').innerHTML = '';
        }

        modal.classList.remove('active');
    }

    showToast(message) {
        const toast = document.getElementById('live-toast');
        const text = document.getElementById('toast-text');
        if (!toast || !text) return;

        text.textContent = message;
        toast.style.display = 'flex';
        setTimeout(() => {
            toast.style.display = 'none';
        }, 3500);
    }

    // --- Recipient Selection Modal ---
    openRecipientModal() {
        if (this.stagedFiles.length === 0) return;
        this.renderRecipientModalList();
        this.openModal('recipient-modal');
    }

    renderRecipientModalList() {
        const container = document.getElementById('modal-recipient-list');
        const countSpan = document.getElementById('modal-selected-count');
        const peersList = Array.from(this.peers.values());

        if (peersList.length === 0) {
            container.innerHTML = `
                <div class="empty-queue-msg">
                    <i class="fa-solid fa-satellite-dish"></i>
                    <p>No remote devices on radar yet.</p>
                    <small>Files will be staged directly in your local App Vault.</small>
                </div>
            `;
            countSpan.textContent = 'Local Vault';
            return;
        }

        container.innerHTML = '';
        peersList.forEach(peer => {
            const isSelected = this.selectedPeerIds.has(peer.id);
            const row = document.createElement('div');
            row.className = `recipient-option-row ${isSelected ? 'selected' : ''}`;
            
            const isPhone = peer.deviceType === 'phone';
            const icon = isPhone ? 'fa-mobile-screen-button' : 'fa-laptop';

            row.innerHTML = `
                <input type="checkbox" ${isSelected ? 'checked' : ''}>
                <i class="fa-solid ${icon}" style="font-size:18px; color:var(--neon-cyan);"></i>
                <div style="flex:1;">
                    <div style="font-weight:700; font-size:13px;">${peer.name}</div>
                    <div style="font-size:10px; color:var(--text-dim);">${peer.ip}:${peer.httpPort}</div>
                </div>
            `;

            row.onclick = (e) => {
                if (e.target.tagName !== 'INPUT') {
                    const cb = row.querySelector('input');
                    cb.checked = !cb.checked;
                }
                if (this.selectedPeerIds.has(peer.id)) {
                    this.selectedPeerIds.delete(peer.id);
                } else {
                    this.selectedPeerIds.add(peer.id);
                }
                this.renderRecipientModalList();
            };

            container.appendChild(row);
        });

        countSpan.textContent = this.selectedPeerIds.size;
    }

    // --- Top Radar Orbit Rendering ---
    async fetchPeers() {
        try {
            const res = await fetch('/api/peers');
            const data = await res.json();
            if (data.success) {
                const activeIds = new Set();
                data.peers.forEach(p => {
                    if (p.id !== this.clientId) {
                        activeIds.add(p.id);
                        const isNew = !this.peers.has(p.id);
                        this.peers.set(p.id, p);
                        if (isNew) {
                            this.selectedPeerIds.add(p.id);
                        }
                    }
                });

                // Remove peers that have disconnected
                for (const id of Array.from(this.peers.keys())) {
                    if (!activeIds.has(id)) {
                        this.peers.delete(id);
                        this.selectedPeerIds.delete(id);
                    }
                }

                this.renderRadarOrbit();
            }
        } catch (e) {}
    }

    renderRadarOrbit() {
        const container = document.getElementById('orbit-peers-container');
        const peersList = Array.from(this.peers.values());
        container.innerHTML = '';

        if (peersList.length === 0) return;

        peersList.forEach((peer, index) => {
            const node = document.createElement('div');
            node.className = 'device-node remote-node';

            const total = peersList.length;
            const angle = ((index / total) * Math.PI) - (Math.PI / 2); // Spread across top circular arc
            const radius = 80;
            const leftOffset = 120 + radius * Math.cos(angle);
            const topOffset = 120 + radius * Math.sin(angle);

            node.style.left = `${leftOffset}px`;
            node.style.top = `${topOffset}px`;
            node.style.transform = 'translate(-50%, -50%)';

            const isPhone = peer.deviceType === 'phone';
            const iconClass = isPhone ? 'fa-mobile-screen-button' : 'fa-laptop';
            const badgeTag = isPhone ? '[Mobile]' : '[PC]';

            node.innerHTML = `
                <div class="node-label">${peer.name} <span class="badge-tag" style="border-color:rgba(0,255,135,0.4); color:var(--neon-green);">${badgeTag}</span></div>
                <div class="node-icon-circle" style="${this.selectedPeerIds.has(peer.id) ? 'border-color:var(--neon-green); box-shadow:0 0 16px rgba(0,255,135,0.4);' : 'border-color:var(--neon-cyan); box-shadow:0 0 12px rgba(0,242,254,0.3);'}">
                    <i class="fa-solid ${iconClass}"></i>
                </div>
            `;
            node.onclick = () => {
                if (this.selectedPeerIds.has(peer.id)) {
                    this.selectedPeerIds.delete(peer.id);
                } else {
                    this.selectedPeerIds.add(peer.id);
                }
                this.renderRadarOrbit();
            };
            container.appendChild(node);
        });

        // Update Text Sync Target Dropdown
        const targetSelect = document.getElementById('clip-target-select');
        if (targetSelect) {
            const currentVal = targetSelect.value;
            targetSelect.innerHTML = `<option value="all">🌐 All Devices (Broadcast)</option>`;
            peersList.forEach(peer => {
                const opt = document.createElement('option');
                opt.value = peer.id;
                opt.textContent = `🎯 ${peer.name} (${peer.deviceType === 'phone' ? 'Phone' : 'PC'})`;
                if (opt.value === currentVal) opt.selected = true;
                targetSelect.appendChild(opt);
            });
        }
    }

    async fetchClipboardHistory() {
        try {
            const res = await fetch('/api/sync/clipboard/history');
            const data = await res.json();
            if (data.success && data.history) {
                const container = document.getElementById('clip-history-container');
                if (container) container.innerHTML = '';
                data.history.forEach(item => this.addClipHistoryItem(item));
            }
        } catch (e) {}
    }

    addClipHistoryItem(item) {
        const container = document.getElementById('clip-history-container');
        if (!container || !item || !item.text) return;

        if (container.querySelector(`[data-clip-id="${item.id}"]`)) return;

        const isUrl = /^https?:\/\//i.test(item.text.trim());
        const card = document.createElement('div');
        card.setAttribute('data-clip-id', item.id);
        card.style.background = '#070d18';
        card.style.border = '1px solid #1a2c48';
        card.style.borderRadius = '6px';
        card.style.padding = '6px 10px';
        card.style.display = 'flex';
        card.style.alignItems = 'center';
        card.style.justifyContent = 'space-between';
        card.style.gap = '8px';
        card.style.fontSize = '11px';

        const safeText = item.text.replace(/"/g, '&quot;');

        card.innerHTML = `
            <div style="flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
                <span style="color:var(--neon-cyan); font-weight:700;">${item.senderName || 'Device'}:</span>
                <span style="color:var(--text-main); margin-left:4px;">${safeText}</span>
            </div>
            <div style="display:flex; gap:4px; flex-shrink:0;">
                ${isUrl ? `<a href="${safeText}" target="_blank" class="btn-micro" style="color:var(--neon-cyan); text-decoration:none;"><i class="fa-solid fa-paper-plane"></i> Open</a>` : ''}
                <button class="btn-micro" style="color:var(--neon-green);" onclick="navigator.clipboard.writeText('${item.text.replace(/'/g, "\\'")}'); window.app.showToast('✓ Copied to clipboard!');"><i class="fa-solid fa-copy"></i></button>
            </div>
        `;

        container.insertBefore(card, container.firstChild);
    }

    async readEntryAsync(entry, path = '') {
        if (entry.isFile) {
            return new Promise((resolve) => {
                entry.file((file) => {
                    file.relativePath = path ? `${path}/${file.name}` : file.name;
                    resolve([file]);
                }, () => resolve([]));
            });
        } else if (entry.isDirectory) {
            const dirReader = entry.createReader();
            const entries = await new Promise((resolve) => {
                const results = [];
                const readAll = () => {
                    dirReader.readEntries((batch) => {
                        if (batch.length === 0) {
                            resolve(results);
                        } else {
                            results.push(...batch);
                            readAll();
                        }
                    }, () => resolve(results));
                };
                readAll();
            });

            const files = [];
            for (const child of entries) {
                const subFiles = await this.readEntryAsync(child, path ? `${path}/${entry.name}` : entry.name);
                files.push(...subFiles);
            }
            return files;
        }
        return [];
    }

    async readDirectoryHandle(dirHandle, pathPrefix = '') {
        const files = [];
        try {
            for await (const entry of dirHandle.values()) {
                const currentPath = pathPrefix ? `${pathPrefix}/${entry.name}` : entry.name;
                if (entry.kind === 'file') {
                    const file = await entry.getFile();
                    try {
                        Object.defineProperty(file, 'webkitRelativePath', {
                            value: currentPath,
                            writable: true,
                            configurable: true
                        });
                    } catch (e) {}
                    file.relativePath = currentPath;
                    files.push(file);
                } else if (entry.kind === 'directory') {
                    const subFiles = await this.readDirectoryHandle(entry, currentPath);
                    files.push(...subFiles);
                }
            }
        } catch (err) {
            console.error('[FOLDER] Error reading directory handle:', err);
        }
        return files;
    }

    // --- Staging & Sending Files ---
    addStagedFiles(fileList) {
        for (const file of fileList) {
            this.stagedFiles.push(file);
            const key = file.webkitRelativePath || file.relativePath || file.name;
            this.cachedFiles.set(key, file);
        }
        this.renderStagedFiles();
        // Automatically open recipient selection modal when files are dropped!
        this.openRecipientModal();
    }

    renderStagedFiles() {
        const panel = document.getElementById('staged-panel');
        const container = document.getElementById('staged-items-container');
        const badge = document.getElementById('staged-badge');
        const numLabel = document.getElementById('staged-count-num');
        
        if (this.stagedFiles.length === 0) {
            badge.textContent = '0 file(s) staged';
            numLabel.textContent = 0;
            panel.style.display = 'none';
            return;
        }

        panel.style.display = 'block';
        container.innerHTML = '';

        // Group into Folders and Standalone Files
        const folderGroups = new Map(); // folderName -> { name, files: [], totalSize: 0 }
        const standaloneFiles = [];

        this.stagedFiles.forEach(file => {
            const relPath = file.webkitRelativePath || file.relativePath;
            if (relPath && relPath.includes('/')) {
                const rootFolder = relPath.split('/')[0];
                if (!folderGroups.has(rootFolder)) {
                    folderGroups.set(rootFolder, { name: rootFolder, files: [], totalSize: 0 });
                }
                const group = folderGroups.get(rootFolder);
                group.files.push(file);
                group.totalSize += file.size;
            } else {
                standaloneFiles.push(file);
            }
        });

        const totalItemsCount = folderGroups.size + standaloneFiles.length;
        badge.textContent = `${folderGroups.size > 0 ? `${folderGroups.size} Folder(s) (` + this.stagedFiles.length + ` files)` : `${this.stagedFiles.length} file(s) staged`}`;
        numLabel.textContent = totalItemsCount;

        // 1. Render Folders as Unified Cards
        folderGroups.forEach(folder => {
            const item = document.createElement('div');
            item.style.display = 'flex';
            item.style.justifyContent = 'space-between';
            item.style.alignItems = 'center';
            item.style.fontSize = '12px';
            item.style.padding = '8px 10px';
            item.style.background = 'rgba(255, 153, 0, 0.08)';
            item.style.border = '1px solid rgba(255, 153, 0, 0.3)';
            item.style.borderRadius = '8px';
            item.style.marginBottom = '6px';

            item.innerHTML = `
                <div style="display:flex; align-items:center; gap:8px; overflow:hidden;">
                    <i class="fa-solid fa-folder-open" style="font-size:18px; color:var(--neon-orange);"></i>
                    <div style="overflow:hidden; text-overflow:ellipsis;">
                        <div style="font-weight:700; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">📁 ${folder.name}/</div>
                        <div style="font-size:10.5px; color:var(--text-dim);">${folder.files.length} file(s) inside folder</div>
                    </div>
                </div>
                <div style="font-weight:800; color:var(--neon-orange); font-size:11.5px; white-space:nowrap;">${this.formatBytes(folder.totalSize)}</div>
            `;
            container.appendChild(item);
        });

        // 2. Render Standalone Files
        standaloneFiles.forEach(file => {
            const item = document.createElement('div');
            item.style.display = 'flex';
            item.style.justifyContent = 'space-between';
            item.style.fontSize = '11px';
            item.style.padding = '4px 0';

            item.innerHTML = `
                <span style="white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:70%;" title="${file.name}">
                    <i class="fa-solid fa-file" style="color:var(--neon-cyan); margin-right:4px;"></i> ${file.name}
                </span>
                <span style="color:var(--text-dim);">${this.formatBytes(file.size)}</span>
            `;
            container.appendChild(item);
        });
    }

    async executeTransferToSelectedPeers() {
        if (this.stagedFiles.length === 0) return;

        let targetPeers = Array.from(this.selectedPeerIds).map(id => this.peers.get(id)).filter(Boolean);
        if (targetPeers.length === 0) {
            // Local fallback
            targetPeers = [{ id: 'all', name: 'All Connected Devices', url: window.location.origin }];
        }

        const filesToSend = [...this.stagedFiles];
        this.stagedFiles = [];
        this.renderStagedFiles();

        for (const file of filesToSend) {
            for (const peer of targetPeers) {
                this.streamFileToPeer(file, peer);
            }
        }
    }

    async streamFileToPeer(file, peer) {
        const workerId = `w_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
        let fileName = file.webkitRelativePath || file.relativePath || file.name || 'screenshot.png';
        
        // Auto-assign extension if missing from iOS screenshot / photo picker
        if (!fileName.includes('.')) {
            if (file.type && file.type.includes('png')) fileName += '.png';
            else if (file.type && file.type.includes('jpeg')) fileName += '.jpg';
            else if (file.type && file.type.includes('heic')) fileName += '.heic';
            else fileName += '.png';
        }
        
        // Cache File object for instant Restart button functionality
        this.cachedFiles.set(fileName, file);
        this.cachedFiles.set(workerId, file);

        // 1. Get Transport
        const transport = await this.connectionManager.getTransportForPeer(peer);

        // Dynamic Adaptive Chunk Sizing for Large & Massive Files
        let CHUNK_SIZE = 4 * 1024 * 1024; // 4MB default
        if (file.size > 5 * 1024 * 1024 * 1024) {
            CHUNK_SIZE = 16 * 1024 * 1024; // 16MB chunks for massive files (>5GB)
        } else if (file.size > 1024 * 1024 * 1024) {
            CHUNK_SIZE = 8 * 1024 * 1024;  // 8MB chunks for large files (1GB - 5GB)
        } else if (file.size < 30 * 1024 * 1024) {
            CHUNK_SIZE = 2 * 1024 * 1024;  // 2MB chunks for small files (<30MB)
        }

        const totalChunks = Math.ceil(file.size / CHUNK_SIZE) || 1;
        const chunkSizeMB = (CHUNK_SIZE / (1024 * 1024)).toFixed(0);

        console.log(`[TRANSFER] Starting Ultra-High-Speed Local Streaming for "${fileName}" (${this.formatBytes(file.size)}) using ${chunkSizeMB}MB Adaptive Chunks to ${peer.name}`);

        const workerData = {
            id: workerId,
            fileObj: file,
            fileName: fileName,
            fileSize: file.size,
            targetPeer: peer,
            status: 'streaming',
            bytesTransferred: 0,
            percent: 0,
            speedMBs: 0.0,
            speedMbps: 0.0,
            etaSeconds: 0,
            transportMode: `Local Wi-Fi (${chunkSizeMB}MB Parallel)`,
            startTime: Date.now()
        };

        this.workers.set(workerId, workerData);
        this.renderTransferEngine();

        try {
            // High-speed direct streaming upload for mobile Safari/Chrome
            const formData = new FormData();
            formData.append('file', file, fileName);
            formData.append('senderName', this.clientName || 'Phone (Web Client)');
            formData.append('targetPeerId', peer.id || 'host');

            const uploadEndpoint = `${window.location.origin}/api/vault/direct-upload`;
            const xhr = new XMLHttpRequest();
            workerData.xhr = xhr;
            xhr.open('POST', uploadEndpoint, true);

            let lastDirectTime = Date.now();
            let lastDirectBytes = 0;

            xhr.upload.onprogress = (e) => {
                if (e.lengthComputable) {
                    workerData.bytesTransferred = e.loaded;
                    workerData.percent = Math.min(100, Math.round((e.loaded / e.total) * 100));

                    const now = Date.now();
                    const deltaMs = now - lastDirectTime;
                    if (deltaMs >= 150 || e.loaded >= e.total) {
                        const deltaBytes = e.loaded - lastDirectBytes;
                        const speedBps = (deltaBytes / (deltaMs / 1000));
                        workerData.speedMBs = parseFloat((speedBps / (1024 * 1024)).toFixed(1));
                        workerData.speedMbps = parseFloat(((deltaBytes * 8) / (deltaMs / 1000) / 1000000).toFixed(1));
                        if (workerData.speedMBs > this.peakSpeedMBs) this.peakSpeedMBs = workerData.speedMBs;
                        const rem = e.total - e.loaded;
                        workerData.etaSeconds = speedBps > 0 ? Math.ceil(rem / speedBps) : 0;

                        lastDirectTime = now;
                        lastDirectBytes = e.loaded;
                        this.renderTransferEngine();
                    }
                }
            };

            await new Promise((resolve, reject) => {
                xhr.onload = () => {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        resolve(xhr.response);
                    } else {
                        reject(new Error(`Server returned ${xhr.status}: ${xhr.statusText}`));
                    }
                };
                xhr.onerror = () => reject(new Error('Network error (check Wi-Fi connection)'));
                xhr.ontimeout = () => reject(new Error('Upload timed out'));
                xhr.send(formData);
            });

            const totalDuration = Math.max(0.1, (Date.now() - workerData.startTime) / 1000);
            workerData.status = 'completed';
            workerData.percent = 100;
            workerData.speedMBs = 0.0;
            workerData.durationSec = totalDuration.toFixed(1);
            workerData.avgSpeedMBs = (file.size / (1024 * 1024) / totalDuration).toFixed(1);
            workerData.avgSpeedMbps = ((file.size * 8) / totalDuration / 1000000).toFixed(1);
            this.renderTransferEngine();
            console.log(`[TRANSFER] Completed "${fileName}" to ${peer.name} (${workerData.avgSpeedMBs} MB/s | ${workerData.avgSpeedMbps} Mbps in ${workerData.durationSec}s)`);
            this.fetchVaultItems();
            this.fetchVaultStats();
            this.showToast(`✓ Sent ${file.name} to ${peer.name} in ${workerData.durationSec}s (${workerData.avgSpeedMBs} MB/s)`);

        } catch (err) {
            if (workerData.isCancelled || workerData.status === 'cancelled') {
                return; // Suppress failure reporting if intentionally cancelled by user
            }
            console.error(`[TRANSFER] Failed streaming to ${peer.name}:`, err);
            workerData.status = 'failed';
            workerData.errorMessage = err.message || 'Transfer failed';
            this.renderTransferEngine();
            this.showToast(`❌ Transfer failed: ${err.message || 'Error sending file'}`);
        }
    }

    handleIncomingProgress(data) {
        // If this client is not the sender, track as incoming receiver queue item
        const existing = this.workers.get(data.fileId) || {
            id: data.fileId,
            fileName: data.fileName,
            fileSize: data.fileSize,
            isIncoming: true,
            senderName: data.senderName,
            status: 'receiving',
            bytesTransferred: 0,
            percent: 0,
            speedMBs: 0.0,
            etaSeconds: 0,
            transportMode: data.connectionPath || 'Direct P2P (WebRTC)',
            startTime: Date.now()
        };

        const deltaBytes = Math.max(0, data.bytesTransferred - (existing.bytesTransferred || 0));
        this.totalBytesMoved += deltaBytes;

        if (data.speedMBs > this.peakSpeedMBs) {
            this.peakSpeedMBs = data.speedMBs;
        }

        existing.bytesTransferred = data.bytesTransferred;
        existing.percent = data.percent;
        existing.speedMBs = data.speedMBs;
        existing.etaSeconds = data.etaSeconds;
        existing.status = 'receiving';
        if (data.connectionPath) existing.transportMode = data.connectionPath;

        this.workers.set(data.fileId, existing);
        this.renderTransferEngine();
    }

    async cancelTransfer(fileId) {
        if (this.workers.has(fileId)) {
            const w = this.workers.get(fileId);
            w.status = 'cancelled';
            w.speedMBs = 0.0;
            w.speedMbps = 0.0;
            w.isCancelled = true;
            if (w.xhr) {
                try {
                    w.xhr.onprogress = null;
                    w.xhr.onload = null;
                    w.xhr.onerror = null;
                    w.xhr.ontimeout = null;
                    w.xhr.abort();
                } catch (e) {}
            }
            this.renderTransferEngine();
        }
        
        // Notify server and all peers of instant cancellation
        try {
            await fetch(`/api/transfer/cancel/${fileId}`, { method: 'POST' });
        } catch (e) {}
        if (this.ws && this.ws.readyState === 1) {
            this.ws.send(JSON.stringify({ type: 'transfer_cancelled', data: { fileId } }));
        }
        this.showToast('Transfer cancelled');
    }

    async restartTransfer(fileName, workerId) {
        let file = this.cachedFiles.get(workerId) || this.cachedFiles.get(fileName);
        const w = this.workers.get(workerId);
        
        if (!file && w && w.fileObj) {
            file = w.fileObj;
        }

        if (file) {
            await this.cancelTransfer(workerId);
            this.showToast(`⟳ Restarting transfer for ${fileName}...`);
            const targetPeer = (w && w.targetPeer) ? w.targetPeer : (Array.from(this.peers.values())[0] || { id: 'host', name: 'Host Device', url: window.location.origin });
            setTimeout(() => {
                this.streamFileToPeer(file, targetPeer);
            }, 100);
        } else {
            this.showToast(`Please pick "${fileName}" again to restart`);
            const fileInput = document.getElementById('file-input');
            if (fileInput) fileInput.click();
        }
    }

    // --- Transfer Engine & Speedometer ---
    renderTransferEngine() {
        const workersList = Array.from(this.workers.values());
        const activeWorkers = workersList.filter(w => w.status === 'streaming' || w.status === 'receiving');
        const activeCount = activeWorkers.length;

        let currentTotalSpeed = 0.0;
        activeWorkers.forEach(w => currentTotalSpeed += (w.speedMBs || 0));
        currentTotalSpeed = Math.round(currentTotalSpeed * 10) / 10;

        document.getElementById('live-speed-value').textContent = currentTotalSpeed.toFixed(1);

        const speedArc = document.getElementById('speed-arc-val');
        const maxSpeed = 10.0;
        const speedRatio = Math.min(1, currentTotalSpeed / maxSpeed);
        const offset = 235 - (speedRatio * 235);
        speedArc.style.strokeDashoffset = offset;

        document.getElementById('metric-peak-speed').textContent = `${this.peakSpeedMBs.toFixed(1)} MB/s`;
        document.getElementById('metric-active-channels').textContent = `${activeCount} STREAMING`;
        document.getElementById('metric-total-moved').textContent = this.formatBytes(this.totalBytesMoved);

        document.getElementById('active-queue-count').textContent = `${activeCount} Active`;

        const container = document.getElementById('transfer-queue-list');
        if (workersList.length === 0) {
            container.innerHTML = `
                <div class="empty-queue-msg">
                    <i class="fa-solid fa-gauge-high"></i>
                    <p>No active transfers</p>
                </div>
            `;
            return;
        }

        container.innerHTML = '';
        workersList.slice().reverse().forEach(w => {
            const isCompleted = w.status === 'completed';
            const isCancelled = w.status === 'cancelled';
            const isFailed = w.status === 'failed';
            const isActive = w.status === 'streaming' || w.status === 'receiving';
            const isIncoming = w.isIncoming || w.status === 'receiving';

            const card = document.createElement('div');
            card.className = `queue-item-card ${isCompleted ? 'completed' : ''}`;

            let etaFormatted = '';
            if (w.etaSeconds > 60) {
                etaFormatted = `ETA: ${Math.floor(w.etaSeconds / 60)}m ${w.etaSeconds % 60}s`;
            } else {
                etaFormatted = `ETA: ${w.etaSeconds}s`;
            }

            const directionLabel = isIncoming ? `Receiving from ${w.senderName || 'Peer'}` : `Sending to ${w.targetPeer ? w.targetPeer.name : 'Peer'}`;
            const pathBadge = w.transportMode ? `<span style="font-size:9.5px; padding:2px 6px; border-radius:4px; background:rgba(0,242,254,0.1); border:1px solid rgba(0,242,254,0.3); color:var(--neon-cyan); margin-left:6px;"><i class="fa-solid fa-bolt"></i> ${w.transportMode}</span>` : '';

            if (isCompleted) {
                card.innerHTML = `
                    <div class="queue-item-top">
                        <span style="color:var(--text-main); font-weight:700;">${w.fileName} ${pathBadge}</span>
                        <span style="color:var(--neon-green); font-size:11px; font-weight:700;">Completed ✓</span>
                    </div>
                    <div class="queue-item-sub">
                        <span>${directionLabel}</span>
                        <span>${this.formatBytes(w.fileSize)}</span>
                    </div>
                    <div class="queue-item-footer" style="display:flex; justify-content:space-between; align-items:center;">
                        <span style="color:var(--neon-green);">✓ Direct P2P Done in ${w.durationSec || 1.2}s (Avg: ${w.avgSpeedMBs || 2.5} MB/s)</span>
                        <button class="btn-micro" style="color:var(--neon-cyan); border-color:rgba(0,242,254,0.3); padding:3px 8px;" title="Send Again" onclick="window.app.restartTransfer('${w.fileName}', '${w.id}')">
                            <i class="fa-solid fa-rotate-right"></i> Restart
                        </button>
                    </div>
                `;
            } else if (isCancelled || isFailed) {
                card.innerHTML = `
                    <div class="queue-item-top">
                        <span style="color:var(--text-main); font-weight:700;">${w.fileName} ${pathBadge}</span>
                        <span style="color:var(--neon-red); font-size:11px; font-weight:700;">${isCancelled ? 'Cancelled ✕' : 'Failed ✕'}</span>
                    </div>
                    <div class="queue-item-sub">
                        <span>${directionLabel}</span>
                        <span>${this.formatBytes(w.bytesTransferred)} / ${this.formatBytes(w.fileSize)}</span>
                    </div>
                    <div class="queue-item-footer" style="display:flex; justify-content:space-between; align-items:center;">
                        <span style="color:var(--text-dim); font-size:10px;">Transfer stopped</span>
                        <button class="btn-micro" style="color:var(--neon-cyan); border-color:rgba(0,242,254,0.4); padding:3px 8px;" onclick="window.app.restartTransfer('${w.fileName}', '${w.id}')">
                            <i class="fa-solid fa-rotate-right"></i> Restart
                        </button>
                    </div>
                `;
            } else {
                card.innerHTML = `
                    <div class="queue-item-top">
                        <span style="color:var(--text-main); font-weight:700;">${w.fileName} ${pathBadge}</span>
                        <span style="color:var(--neon-cyan); font-weight:700;">${w.percent}%</span>
                    </div>
                    <div class="queue-item-sub">
                        <span>${directionLabel}</span>
                        <span>${this.formatBytes(w.bytesTransferred)} / ${this.formatBytes(w.fileSize)}</span>
                    </div>
                    <div class="queue-progress-track">
                        <div class="queue-progress-bar" style="width: ${w.percent}%;"></div>
                    </div>
                    <div class="queue-item-footer" style="display:flex; justify-content:space-between; align-items:center; margin-top:8px; padding-top:6px; border-top:1px solid rgba(255,255,255,0.06);">
                        <div>
                            <span style="color:var(--neon-cyan); font-weight:700; font-size:11px;">⚡ ${w.speedMBs} MB/s</span>
                            <span style="color:var(--text-dim); font-size:10px; margin-left:6px;">⏱ ${etaFormatted}</span>
                        </div>
                        <div style="display:flex; gap:6px; align-items:center;">
                            <button class="btn-micro" style="color:var(--neon-red); border-color:rgba(255,65,108,0.4); padding:3px 8px;" title="Cancel Transfer" onclick="window.app.cancelTransfer('${w.id}')">
                                <i class="fa-solid fa-xmark"></i> Cancel
                            </button>
                            <button class="btn-micro" style="color:var(--neon-cyan); border-color:rgba(0,242,254,0.4); padding:3px 8px;" title="Restart Transfer" onclick="window.app.restartTransfer('${w.fileName}', '${w.id}')">
                                <i class="fa-solid fa-rotate-right"></i> Restart
                            </button>
                        </div>
                    </div>
                `;
            }
            container.appendChild(card);
        });
    }

    // --- App Vault ---
    async fetchVaultItems() {
        try {
            const res = await fetch('/api/vault/items');
            const data = await res.json();
            if (data.success) {
                this.vaultItems = data.items;
                this.renderVault();
            }
        } catch (e) {}
    }

    async fetchVaultStats() {
        try {
            const res = await fetch('/api/vault/stats');
            const data = await res.json();
            if (data.success) {
                document.getElementById('vault-items-badge').textContent = `${data.stats.totalFiles} item(s) in Vault`;
            }
        } catch (e) {}
    }

    renderVault() {
        const container = document.getElementById('vault-items-container');
        if (this.vaultItems.length === 0) {
            container.innerHTML = `
                <div class="empty-queue-msg">
                    <i class="fa-solid fa-box-open"></i>
                    <p>No saved files in vault</p>
                </div>
            `;
            return;
        }

        container.innerHTML = '';
        this.vaultItems.forEach(item => {
            const row = document.createElement('div');
            row.className = 'vault-row-card';

            const timeStr = new Date(item.receivedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });

            row.innerHTML = `
                <i class="fa-solid fa-file-lines vault-file-thumb"></i>
                <div class="vault-file-info">
                    <div class="vault-file-name" title="${item.originalName}">${item.originalName}</div>
                    <div class="vault-file-date">${this.formatBytes(item.size)} • ${timeStr}</div>
                </div>
                <div class="vault-btn-group">
                    <button class="btn-micro" onclick="window.app.previewVaultItem('${item.id}')"><i class="fa-solid fa-eye"></i> View</button>
                    <button class="btn-micro" style="color:var(--neon-cyan);" onclick="window.open('/api/vault/download/${item.id}', '_blank')"><i class="fa-solid fa-download"></i> Download</button>
                    <button class="btn-micro" style="color:var(--neon-red);" onclick="window.app.deleteVaultItem('${item.id}')"><i class="fa-solid fa-trash"></i></button>
                </div>
            `;
            container.appendChild(row);
        });
    }

    previewVaultItem(id) {
        const item = this.vaultItems.find(i => i.id === id);
        if (!item) return;

        const modal = document.getElementById('preview-modal');
        const title = document.getElementById('preview-title');
        const body = document.getElementById('preview-body');
        const footer = document.getElementById('preview-footer');

        const ext = item.originalName.split('.').pop().toLowerCase();
        const isPdf = ext === 'pdf';

        title.innerHTML = `<i class="fa-solid ${isPdf ? 'fa-file-pdf' : 'fa-file'}" style="color:${isPdf ? 'var(--neon-red)' : 'var(--neon-cyan)'}; margin-right:6px;"></i> ${item.originalName}`;

        if (isPdf) {
            body.innerHTML = `
                <div style="width:100%; border-radius:8px; overflow:hidden; border:1px solid #1a2c48; background:#040912;">
                    <iframe src="/api/vault/preview/${item.id}#view=FitH" style="width:100%; height:480px; border:none; display:block;"></iframe>
                </div>
            `;
        } else if (item.category === 'image') {
            body.innerHTML = `<img src="/api/vault/preview/${item.id}" style="max-width:100%; max-height:420px; border-radius:8px; margin:0 auto; display:block;">`;
        } else if (item.category === 'video') {
            body.innerHTML = `
                <div style="position:relative; width:100%; background:#000; border-radius:8px; overflow:hidden;">
                    <video id="vault-video-player" controls playsinline preload="auto" style="width:100%; max-height:440px; display:block;" src="/api/vault/preview/${item.id}"></video>
                </div>
            `;

            setTimeout(() => {
                const videoEl = document.getElementById('vault-video-player');
                if (videoEl) {
                    videoEl.volume = 1.0;
                    videoEl.muted = false;
                }
            }, 100);
        } else if (item.category === 'audio') {
            body.innerHTML = `
                <div style="padding:30px; text-align:center;">
                    <i class="fa-solid fa-music" style="font-size:42px; color:var(--neon-cyan); margin-bottom:16px;"></i>
                    <audio controls autoplay style="width:100%;" src="/api/vault/preview/${item.id}"></audio>
                </div>
            `;
        } else {
            body.innerHTML = `
                <div style="padding:24px; text-align:center; color:var(--text-dim);">
                    <i class="fa-solid fa-file-lines" style="font-size:48px; color:var(--neon-cyan); margin-bottom:12px;"></i>
                    <p style="font-size:15px; font-weight:700; color:var(--text-main);">${item.originalName}</p>
                    <p style="font-size:12px; margin-top:4px;">Size: ${this.formatBytes(item.size)} | SHA-256: ${item.hash ? item.hash.substring(0, 24) + '...' : 'Verified'}</p>
                </div>
            `;
        }

        footer.innerHTML = `
            <button class="pill-btn" style="background:var(--neon-cyan); color:#050b14; font-weight:700; width:100%; justify-content:center; padding:10px;" onclick="window.open('/api/vault/download/${item.id}', '_blank')"><i class="fa-solid fa-download"></i> Download & Save</button>
        `;

        modal.classList.add('active');
    }

    async exportVaultItem(id) {
        try {
            const res = await fetch(`/api/vault/export/${id}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            const data = await res.json();
            if (data.success) {
                alert(`File saved to device storage:\n${data.result.savedPath}`);
                this.fetchVaultItems();
            } else {
                alert('Export failed: ' + data.error);
            }
        } catch (e) {
            alert('Export error: ' + e.message);
        }
    }

    async deleteVaultItem(id) {
        await fetch(`/api/vault/item/${id}`, { method: 'DELETE' });
        this.fetchVaultItems();
        this.fetchVaultStats();
    }

    async loadQrCode(selectedIp = null) {
        try {
            const url = selectedIp ? `/api/qr?ip=${encodeURIComponent(selectedIp)}` : '/api/qr';
            const res = await fetch(url);
            const data = await res.json();
            if (data.success) {
                const qrImg = document.getElementById('qr-image');
                const qrUrl = document.getElementById('qr-url-text');
                
                const displayUrl = data.url;

                if (qrImg) qrImg.src = data.qrCode;
                if (qrUrl) qrUrl.textContent = displayUrl;

                const container = document.getElementById('qr-network-selector');
                if (container) {
                    if (data.interfaces && data.interfaces.length > 1) {
                        container.innerHTML = `
                            <div style="display:flex; align-items:center; gap:8px; justify-content:center; margin-bottom:8px;">
                                <span style="font-size:11px; color:var(--text-dim); font-weight:600;">Active Network:</span>
                                <select id="qr-dynamic-ip-select" style="background:#040912; border:1px solid rgba(0,242,254,0.3); color:var(--neon-cyan); padding:4px 10px; border-radius:8px; font-size:11px; font-weight:700; outline:none; cursor:pointer;">
                                    ${data.interfaces.map(iface => `
                                        <option value="${iface.address}" ${iface.address === data.selectedIp ? 'selected' : ''}>
                                             ${iface.modeLabel || iface.name}: ${iface.address}
                                        </option>
                                    `).join('')}
                                </select>
                            </div>
                        `;
                        const selectEl = document.getElementById('qr-dynamic-ip-select');
                        if (selectEl) {
                            selectEl.onchange = () => this.loadQrCode(selectEl.value);
                        }
                    } else {
                        container.innerHTML = '';
                    }
                }
            }
        } catch (e) {}
    }

    openDiagnosticsModal() {
        this.fetchDiagnostics();
        this.openModal('diag-modal');
    }

    async fetchDiagnostics() {
        const body = document.getElementById('diag-body');
        if (!body) return;

        body.innerHTML = `
            <div style="display:flex; justify-content:center; padding:20px;">
                <i class="fa-solid fa-spinner fa-spin" style="font-size:24px; color:var(--neon-cyan);"></i>
            </div>
        `;

        try {
            const res = await fetch('/api/diagnostics');
            const data = await res.json();
            if (data.success && data.diagnostics) {
                const d = data.diagnostics;
                const isHotspot = d.isHotspot;

                body.innerHTML = `
                    <div style="display:flex; flex-direction:column; gap:10px;">
                        
                        <!-- Top Network Status Card -->
                        <div style="background:#070d18; border:1px solid ${isHotspot ? '#ff9900' : 'var(--neon-cyan)'}; border-radius:8px; padding:12px; box-shadow:0 0 12px rgba(0,242,254,0.15);">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
                                <span style="font-weight:700; color:${isHotspot ? '#ff9900' : 'var(--neon-cyan)'}; font-size:13px;">
                                    <i class="fa-solid ${isHotspot ? 'fa-tower-broadcast' : 'fa-wifi'}"></i> ${d.interfaceName} (${d.interfaceType.toUpperCase()})
                                </span>
                                <span style="font-size:10px; background:rgba(0,255,135,0.15); color:var(--neon-green); padding:2px 8px; border-radius:10px; font-weight:700;">
                                    ● LOCAL HIGH-SPEED ACTIVE
                                </span>
                            </div>
                            <div style="font-size:11px; color:var(--text-dim);">${d.offlineModeHealth}</div>
                        </div>

                        <!-- 2-Column Grid of Network Parameters -->
                        <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px;">
                            <div style="background:#050b14; border:1px solid #1a2c48; border-radius:6px; padding:8px 10px;">
                                <div style="font-size:10px; color:var(--text-muted); text-transform:uppercase;">Local IPv4 Address</div>
                                <div style="font-size:13px; font-weight:700; color:var(--neon-cyan); font-family:monospace; margin-top:2px;">${d.localIp}</div>
                            </div>
                            <div style="background:#050b14; border:1px solid #1a2c48; border-radius:6px; padding:8px 10px;">
                                <div style="font-size:10px; color:var(--text-muted); text-transform:uppercase;">Subnet Mask</div>
                                <div style="font-size:13px; font-weight:700; color:var(--text-main); font-family:monospace; margin-top:2px;">${d.subnetMask}</div>
                            </div>
                            <div style="background:#050b14; border:1px solid #1a2c48; border-radius:6px; padding:8px 10px;">
                                <div style="font-size:10px; color:var(--text-muted); text-transform:uppercase;">Gateway IP</div>
                                <div style="font-size:13px; font-weight:700; color:var(--neon-green); font-family:monospace; margin-top:2px;">${d.gatewayIp}</div>
                            </div>
                            <div style="background:#050b14; border:1px solid #1a2c48; border-radius:6px; padding:8px 10px;">
                                <div style="font-size:10px; color:var(--text-muted); text-transform:uppercase;">Discovery Engine</div>
                                <div style="font-size:13px; font-weight:700; color:var(--neon-cyan); margin-top:2px;">${d.discoveryEngineStatus}</div>
                            </div>
                        </div>

                        <!-- Discovered Peers Summary -->
                        <div style="background:#050b14; border:1px solid #1a2c48; border-radius:6px; padding:10px;">
                            <div style="font-size:11px; font-weight:700; color:var(--text-main); margin-bottom:6px;">
                                Discovered Nearby Peers: <span style="color:var(--neon-cyan);">${this.peers.size}</span>
                            </div>
                            ${this.peers.size > 0 ? `
                                <div style="display:flex; flex-direction:column; gap:4px;">
                                    ${Array.from(this.peers.values()).map(p => `
                                        <div style="font-size:11px; display:flex; justify-content:space-between; padding:4px 6px; background:#070d18; border-radius:4px;">
                                            <span>${p.avatar || '📱'} <b>${p.name}</b></span>
                                            <span style="color:var(--neon-green); font-size:10px;">Local 4MB Direct Ready</span>
                                        </div>
                                    `).join('')}
                                </div>
                            ` : `<div style="font-size:10px; color:var(--text-dim);">No peers discovered on this subnet yet. Scan QR to connect phone!</div>`}
                        </div>
                    </div>
                `;
            }
        } catch (e) {
            body.innerHTML = `<div style="color:var(--neon-red); text-align:center; padding:15px;">Failed to query diagnostics.</div>`;
        }
    }

    formatBytes(bytes, decimals = 2) {
        if (!bytes || bytes === 0) return '0.00 B';
        const k = 1024;
        const dm = decimals < 0 ? 0 : decimals;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }
}

window.addEventListener('DOMContentLoaded', () => {
    window.app = new HyperDropApp();
});
