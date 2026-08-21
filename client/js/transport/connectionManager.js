/**
 * ConnectionManager
 * Manages hybrid transport selection between Local LAN/Hotspot and Remote WebRTC.
 * 
 * Policy:
 *  - IF peer is on local LAN / Hotspot -> USE LocalTransport (Priority 1, fastest, 0-internet, 4MB chunks)
 *  - ELSE IF peer is remote -> USE WebRTCTransport (Priority 2, P2P via STUN, fallback to TURN relay)
 */
class ConnectionManager {
    constructor(app) {
        this.app = app;
        this.transports = new Map(); // peerId -> WebRTCTransport
        this.remoteSessions = new Map(); // sessionId -> WebRTCTransport
        this.iceConfig = {
            iceServers: [
                { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302', 'stun:global.stun.twilio.com:3478'] }
            ]
        };
        this.initIceConfig();
    }

    async initIceConfig() {
        try {
            const res = await fetch('/api/remote/ice-config');
            const data = await res.json();
            if (data.success && data.iceConfig) {
                this.iceConfig = data.iceConfig;
            }
        } catch (e) {}
    }

    /**
     * Determines and retrieves the direct WebRTC P2P transport for a target peer
     */
    async getTransportForPeer(peer) {
        // Return existing active transport if connected or connecting
        if (this.transports.has(peer.id)) {
            const t = this.transports.get(peer.id);
            if (t.status === 'connected' || t.status === 'connecting') return t;
        }

        if (peer.sessionId && this.remoteSessions.has(peer.sessionId)) {
            const t = this.remoteSessions.get(peer.sessionId);
            if (t.status === 'connected' || t.status === 'connecting') return t;
        }

        console.log(`[CONNECTION] Initializing Direct WebRTC Transport for ${peer.name} (${peer.id})`);
        const transport = new WebRTCTransport(peer, this.app.ws, {
            clientId: this.app.clientId,
            clientName: this.app.clientName,
            isHost: peer.isHost !== false,
            iceConfig: this.iceConfig
        });

        this.transports.set(peer.id, transport);
        if (peer.sessionId) {
            this.remoteSessions.set(peer.sessionId, transport);
        }
        return transport;
    }

    _findOrCreateTransport(data) {
        if (data.sessionId && this.remoteSessions.has(data.sessionId)) {
            return this.remoteSessions.get(data.sessionId);
        }
        if (data.senderId && this.transports.has(data.senderId)) {
            return this.transports.get(data.senderId);
        }
        if (data.targetPeerId && this.transports.has(data.targetPeerId)) {
            return this.transports.get(data.targetPeerId);
        }

        // Create receiver transport if incoming offer from an existing peer
        const senderPeer = this.app.peers.get(data.senderId) || {
            id: data.senderId,
            name: data.senderName || 'Peer',
            sessionId: data.sessionId,
            isRemote: true,
            isHost: false
        };

        const transport = new WebRTCTransport(senderPeer, this.app.ws, {
            clientId: this.app.clientId,
            clientName: this.app.clientName,
            isHost: false,
            iceConfig: data.iceConfig || this.iceConfig
        });

        if (senderPeer.id) this.transports.set(senderPeer.id, transport);
        if (data.sessionId) this.remoteSessions.set(data.sessionId, transport);
        return transport;
    }

    handleRemoteSignalingMessage(type, data) {
        if (!data) return;

        switch (type) {
            case 'webrtc_offer': {
                const transport = this._findOrCreateTransport(data);
                if (transport) {
                    transport.handleRemoteOffer(data.sdp);
                }
                break;
            }

            case 'webrtc_answer': {
                const transport = this._findOrCreateTransport(data);
                if (transport) {
                    transport.handleRemoteAnswer(data.sdp);
                }
                break;
            }

            case 'webrtc_ice_candidate': {
                const transport = this._findOrCreateTransport(data);
                if (transport) {
                    transport.handleRemoteIceCandidate(data.candidate);
                }
                break;
            }

            case 'remote_transfer_request': {
                // Show Receiver Authorization Dialog
                this.app.promptReceiverAuthorization(data);
                break;
            }

            case 'remote_transfer_response': {
                if (data.accepted) {
                    this.app.showToast(`✓ ${data.receiverName || 'Peer'} accepted transfer!`);
                } else {
                    this.app.showToast(`❌ ${data.receiverName || 'Peer'} rejected transfer.`);
                }
                break;
            }
        }
    }
}

if (typeof window !== 'undefined') {
    window.ConnectionManager = ConnectionManager;
}
if (typeof module !== 'undefined') {
    module.exports = ConnectionManager;
}
