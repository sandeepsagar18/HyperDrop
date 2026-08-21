/**
 * ConnectionManager
 * Manages high-speed local transport for Same Wi-Fi, Offline, and Mobile Hotspot networks.
 * Uses 4MB chunks for maximum local throughput (50-100+ MB/s) with zero cloud dependencies.
 */
class ConnectionManager {
    constructor(app) {
        this.app = app;
        this.transports = new Map(); // peerId -> LocalTransport
    }

    /**
     * Retrieves the high-speed LocalTransport for a target peer
     */
    async getTransportForPeer(peer) {
        if (this.transports.has(peer.id)) {
            return this.transports.get(peer.id);
        }

        console.log(`[CONNECTION] Mode: LOCAL WI-FI / HOTSPOT | Peer: ${peer.name} (${peer.id})`);
        const transport = new LocalTransport(peer, {
            chunkSize: 4 * 1024 * 1024 // 4MB chunks for maximum local Wi-Fi / Hotspot speed
        });

        this.transports.set(peer.id, transport);
        return transport;
    }

    closeAll() {
        this.transports.clear();
    }
}

if (typeof window !== 'undefined') {
    window.ConnectionManager = ConnectionManager;
}
if (typeof module !== 'undefined') {
    module.exports = ConnectionManager;
}

