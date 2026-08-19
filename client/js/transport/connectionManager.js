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
        this.transports = new Map(); // peerId -> TransferTransport instance
        this.remoteSessions = new Map(); // sessionId -> WebRTCTransport
        this.iceConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };
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
     * Determines best available transport for target peer
     */
    async getTransportForPeer(peer) {
        // Return existing active transport if available
        if (this.transports.has(peer.id)) {
            const t = this.transports.get(peer.id);
            if (t.status === 'connected') return t;
        }

        // 1. Is Remote Peer?
        if (peer.isRemote || peer.sessionId) {
            console.log(`[CONNECTION] Selected Remote WebRTC Transport for ${peer.name}`);
            const transport = new WebRTCTransport(peer, this.app.ws, {
                isHost: peer.isHost !== false,
                iceConfig: this.iceConfig
            });
            this.transports.set(peer.id, transport);
            if (peer.sessionId) {
                this.remoteSessions.set(peer.sessionId, transport);
            }
            return transport;
        }

        // 2. Default: Local Transport (LAN / Hotspot)
        console.log(`[CONNECTION] Selected Local HTTP Streaming Transport for ${peer.name}`);
        const transport = new LocalTransport(peer);
        this.transports.set(peer.id, transport);
        return transport;
    }

    handleRemoteSignalingMessage(type, data) {
        switch (type) {
            case 'webrtc_offer': {
                const transport = this.remoteSessions.get(data.sessionId);
                if (transport) {
                    transport.handleRemoteOffer(data.sdp);
                }
                break;
            }

            case 'webrtc_answer': {
                const transport = this.remoteSessions.get(data.sessionId);
                if (transport) {
                    transport.handleRemoteAnswer(data.sdp);
                }
                break;
            }

            case 'webrtc_ice_candidate': {
                const transport = this.remoteSessions.get(data.sessionId);
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
                    this.app.showToast(`✓ ${data.receiverName || 'Remote Peer'} accepted transfer!`);
                } else {
                    this.app.showToast(`❌ ${data.receiverName || 'Remote Peer'} rejected transfer.`);
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
