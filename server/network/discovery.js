const dgram = require('dgram');
const os = require('os');
const { EventEmitter } = require('events');
const { getNetworkInterfaces } = require('./interfaces');
const { getArpConnectedDevices, probeDevice } = require('./autoScanner');

const DISCOVERY_PORT = 35432;
const BEACON_INTERVAL_MS = 2000;
const ARP_SCAN_INTERVAL_MS = 3000;
const PEER_TIMEOUT_MS = 15000;

class DiscoveryEngine extends EventEmitter {
    constructor(deviceInfo = {}) {
        super();
        this.deviceId = deviceInfo.id || `hd_${Math.random().toString(36).substring(2, 9)}`;
        
        let dynamicName = 'Windows PC';
        try {
            const user = os.userInfo ? os.userInfo().username : (process.env.USERNAME || process.env.USER);
            if (user && user.toLowerCase() !== 'user') {
                dynamicName = `${user}'s PC`;
            } else if (os.hostname()) {
                dynamicName = os.hostname();
            }
        } catch (_) {
            dynamicName = os.hostname() || 'Windows PC';
        }

        this.deviceName = deviceInfo.name || dynamicName;
        this.deviceType = deviceInfo.type || (os.platform() === 'win32' || os.platform() === 'darwin' || os.platform() === 'linux' ? 'laptop' : 'phone');
        this.osType = os.type() + ' ' + os.release();
        this.httpPort = deviceInfo.httpPort || 3000;
        this.avatar = deviceInfo.avatar || '💻';

        this.peers = new Map(); // key: deviceId -> { ...peerData, lastSeen: timestamp }
        this.socket = null;
        this.beaconTimer = null;
        this.arpScanTimer = null;
        this.cleanupTimer = null;
        this.isRunning = false;
    }

    start() {
        if (this.isRunning) return;

        this.socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });

        this.socket.on('error', (err) => {
            console.error('[DISCOVERY] UDP Socket error:', err.message);
        });

        this.socket.on('message', (msg, rinfo) => {
            this._handleIncomingPacket(msg, rinfo);
        });

        this.socket.on('listening', () => {
            try {
                this.socket.setBroadcast(true);
            } catch (e) {}
            const address = this.socket.address();
            console.log(`[DISCOVERY] Peer Discovery active on ${address.address}:${address.port}`);
            this.isRunning = true;

            // 1. Proactive Subnet & Universal Broadcast (every 1.5s)
            this.beaconTimer = setInterval(() => this._broadcastBeacon(), 1500);
            this._broadcastBeacon();

            // 2. Active Hotspot & Subnet Probe (every 3s)
            this.arpScanTimer = setInterval(() => this._scanArpAndSubnet(), 3000);
            this._scanArpAndSubnet();

            // 3. Stale peer cleanup (every 4s)
            this.cleanupTimer = setInterval(() => this._cleanupStalePeers(), 4000);
        });

        try {
            this.socket.bind(DISCOVERY_PORT);
        } catch (err) {
            console.error('[DISCOVERY] Failed to bind UDP port:', err.message);
        }
    }

    stop() {
        if (this.beaconTimer) clearInterval(this.beaconTimer);
        if (this.arpScanTimer) clearInterval(this.arpScanTimer);
        if (this.cleanupTimer) clearInterval(this.cleanupTimer);
        if (this.socket) {
            try {
                this.socket.close();
            } catch (e) {}
        }
        this.isRunning = false;
        this.peers.clear();
    }

    getPeers() {
        return Array.from(this.peers.values());
    }

    onNetworkChanged({ previousIp, newIp, diagnostics }) {
        console.log(`[DISCOVERY] Handling network change (${previousIp} -> ${newIp}). Clearing stale peers.`);
        this.peers.clear();
        this.emit('peers_reset');
        // Immediately broadcast on the new subnet
        this._broadcastBeacon();
        this._scanArpAndSubnet();
    }

    async _scanArpAndSubnet() {
        if (!this.isRunning) return;
        try {
            const interfaces = getNetworkInterfaces();
            const ownIps = interfaces.map(i => i.address);

            // 1. Active Gateway Probing for Hotspot Modes (Android: 192.168.43.1, iOS: 172.20.10.1)
            for (const iface of interfaces) {
                let targetGateway = null;
                if (iface.address.startsWith('192.168.43.')) {
                    targetGateway = '192.168.43.1';
                } else if (iface.address.startsWith('172.20.10.')) {
                    targetGateway = '172.20.10.1';
                }

                if (targetGateway && !ownIps.includes(targetGateway)) {
                    this._probeAndRegisterPeer(targetGateway);
                }
            }

            // 2. ARP-based discovery
            const connectedIps = await getArpConnectedDevices();
            for (const ip of connectedIps) {
                if (ownIps.includes(ip) || ip === '127.0.0.1') continue;
                this._probeAndRegisterPeer(ip);
            }
        } catch (err) {}
    }

    async _probeAndRegisterPeer(ip) {
        const interfaces = getNetworkInterfaces();
        const ownIps = interfaces.map(i => i.address);
        if (ownIps.includes(ip) || ip === '127.0.0.1') return;

        const existingId = Array.from(this.peers.keys()).find(k => this.peers.get(k).ip === ip);
        if (existingId) {
            const peer = this.peers.get(existingId);
            peer.lastSeen = Date.now();
            return;
        }

        // Try standard ports (3000, 8080)
        for (const port of [this.httpPort, 8080, 3000]) {
            const probeRes = await probeDevice(ip, port);
            if (probeRes && probeRes.isHyperDrop && probeRes.data) {
                const peerId = probeRes.data.deviceId || `hd_${ip.replace(/[^a-zA-Z0-9]/g, '_')}`;
                if (peerId === this.deviceId) continue;

                const peerData = {
                    id: peerId,
                    name: probeRes.data.deviceName || (probeRes.data.deviceType === 'phone' ? 'Android / iPhone' : 'Nearby Laptop'),
                    deviceType: probeRes.data.deviceType || 'phone',
                    osType: probeRes.data.osType || 'Wireless Peer',
                    avatar: (probeRes.data.deviceType === 'phone') ? '📱' : '💻',
                    ip,
                    httpPort: port,
                    url: `http://${ip}:${port}`,
                    isAutoDiscovered: true,
                    lastSeen: Date.now()
                };

                this.peers.set(peerId, peerData);
                console.log(`[DISCOVERY] Peer discovered via probe: ${peerData.name} (${peerData.ip}:${peerData.httpPort})`);
                this.emit('peer_discovered', peerData);
                break;
            }
        }
    }

    registerWebClient({ id, name, deviceType, osType, avatar, ip, httpPort }) {
        const peerId = id || `web_${ip.replace(/[^a-zA-Z0-9]/g, '_')}`;
        const isNew = !this.peers.has(peerId);

        const peerData = {
            id: peerId,
            name: name || (deviceType === 'phone' ? 'Android Phone' : 'Nearby Laptop'),
            deviceType: deviceType || 'phone',
            osType: osType || 'Web Client',
            avatar: avatar || (deviceType === 'phone' ? '📱' : '💻'),
            ip: ip || '127.0.0.1',
            httpPort: httpPort || this.httpPort,
            url: `http://${ip}:${httpPort || this.httpPort}`,
            isWebClient: true,
            lastSeen: Date.now()
        };

        this.peers.set(peerId, peerData);

        if (isNew) {
            console.log(`[DISCOVERY] Registered active Web Client peer: ${peerData.name} (${peerData.ip})`);
            this.emit('peer_discovered', peerData);
        } else {
            this.emit('peer_updated', peerData);
        }

        return peerData;
    }

    _handleIncomingPacket(msg, rinfo) {
        try {
            const data = JSON.parse(msg.toString('utf8'));
            const interfaces = getNetworkInterfaces();
            const ownIps = interfaces.map(i => i.address);
            if (!data || data.type !== 'HYPERDROP_BEACON' || data.id === this.deviceId || ownIps.includes(rinfo.address) || rinfo.address === '127.0.0.1') {
                return;
            }

            const peerId = data.id;
            const isNew = !this.peers.has(peerId);

            const peerData = {
                id: peerId,
                name: data.name,
                deviceType: data.deviceType,
                osType: data.osType,
                avatar: data.avatar,
                ip: rinfo.address,
                httpPort: data.httpPort,
                url: `http://${rinfo.address}:${data.httpPort}`,
                isWebClient: false,
                lastSeen: Date.now()
            };

            this.peers.set(peerId, peerData);

            if (isNew) {
                console.log(`[DISCOVERY] UDP Peer discovered: ${peerData.name} at ${peerData.ip}:${peerData.httpPort}`);
                this.emit('peer_discovered', peerData);
            } else {
                this.emit('peer_updated', peerData);
            }
        } catch (err) {}
    }

    _broadcastBeacon() {
        if (!this.socket || !this.isRunning) return;

        const interfaces = getNetworkInterfaces();
        const payload = Buffer.from(JSON.stringify({
            type: 'HYPERDROP_BEACON',
            id: this.deviceId,
            name: this.deviceName,
            deviceType: this.deviceType,
            osType: this.osType,
            avatar: this.avatar,
            httpPort: this.httpPort
        }));

        for (const iface of interfaces) {
            try {
                if (iface.broadcast) {
                    this.socket.send(payload, 0, payload.length, DISCOVERY_PORT, iface.broadcast);
                }
                this.socket.send(payload, 0, payload.length, DISCOVERY_PORT, '255.255.255.255');
            } catch (err) {}
        }
    }

    _cleanupStalePeers() {
        const now = Date.now();
        for (const [peerId, peer] of this.peers.entries()) {
            if (now - peer.lastSeen > PEER_TIMEOUT_MS) {
                this.peers.delete(peerId);
                this.emit('peer_lost', peer);
            }
        }
    }

    manualAddPeer(ip, port, name = 'Direct Connected Device') {
        const peerId = `direct_${ip.replace(/[^a-zA-Z0-9]/g, '_')}_${port}`;
        const peerData = {
            id: peerId,
            name,
            deviceType: 'phone',
            osType: 'Direct Connection',
            avatar: '📱',
            ip,
            httpPort: port,
            url: `http://${ip}:${port}`,
            lastSeen: Date.now()
        };
        this.peers.set(peerId, peerData);
        console.log(`[DISCOVERY] Manually added peer: ${peerData.name} at ${peerData.ip}:${peerData.httpPort}`);
        this.emit('peer_discovered', peerData);
        return peerData;
    }
}

module.exports = DiscoveryEngine;
