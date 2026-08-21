/**
 * ConnectionManager
 * Manages direct peer-to-peer WebRTCTransport instances for high-speed device-to-device streaming.
 * 
 * Data Plane: 100% Direct RTCDataChannel (Zero file bytes sent to Render or Cloud)
 * Control Plane: WebSocket signaling only (SDP offers/answers and ICE candidates)
 */
class ConnectionManager {
    constructor(app) {
        this.app = app;
        this.transports = new Map(); // peerId -> WebRTCTransport
        this.iceConfig = {
            iceServers: [
                { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302', 'stun:global.stun.twilio.com:3478'] }
            ]
        };
    }

    /**
     * Retrieves or creates the direct WebRTC P2P transport for a target peer
     */
    async getTransportForPeer(peer) {
        if (this.transports.has(peer.id)) {
            const t = this.transports.get(peer.id);
            if (t.status === 'connected' || t.status === 'connecting') return t;
        }

        console.log(`[CONNECTION] Initializing Direct WebRTC DataChannel Transport for ${peer.name} (${peer.id})`);
        const transport = new WebRTCTransport(peer, this.app.ws, {
            clientId: this.app.clientId,
            clientName: this.app.clientName,
            isHost: true,
            iceConfig: this.iceConfig
        });

        this.transports.set(peer.id, transport);
        return transport;
    }

    _findOrCreateTransport(data) {
        if (data.senderId && this.transports.has(data.senderId)) {
            return this.transports.get(data.senderId);
        }
        if (data.targetPeerId && this.transports.has(data.targetPeerId)) {
            return this.transports.get(data.targetPeerId);
        }

        const senderPeer = this.app.peers.get(data.senderId) || {
            id: data.senderId,
            name: data.senderName || 'Peer',
            isHost: false
        };

        const transport = new WebRTCTransport(senderPeer, this.app.ws, {
            clientId: this.app.clientId,
            clientName: this.app.clientName,
            isHost: false,
            iceConfig: this.iceConfig
        });

        if (senderPeer.id) this.transports.set(senderPeer.id, transport);
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
        }
    }

    closeAll() {
        this.transports.forEach(t => t.close());
        this.transports.clear();
    }
}

if (typeof window !== 'undefined') {
    window.ConnectionManager = ConnectionManager;
}
if (typeof module !== 'undefined') {
    module.exports = ConnectionManager;
}


