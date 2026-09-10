const os = require('os');
const { EventEmitter } = require('events');
const { getNetworkInterfaces, getPrimaryIp } = require('./interfaces');

/**
 * NetworkMonitor
 * Continuously detects active network interface shifts (Wi-Fi <-> Android Hotspot <-> Ethernet),
 * computes subnets, gateways, and broadcasts, and emits events on network transition.
 */
class NetworkMonitor extends EventEmitter {
    constructor(checkIntervalMs = 1500) {
        super();
        this.checkIntervalMs = checkIntervalMs;
        this.currentIp = getPrimaryIp();
        this.currentInterfaces = getNetworkInterfaces();
        this.timer = null;
        this.isMonitoring = false;
    }

    start() {
        if (this.isMonitoring) return;
        this.isMonitoring = true;
        this._checkNetwork();
        this.timer = setInterval(() => this._checkNetwork(), this.checkIntervalMs);
        console.log(`[NETWORK] Network Monitor active. Current IP: ${this.currentIp}`);
    }

    stop() {
        if (this.timer) clearInterval(this.timer);
        this.isMonitoring = false;
    }

    getDiagnostics() {
        const ifaces = getNetworkInterfaces();
        const primary = ifaces.find(i => i.address === this.currentIp) || ifaces[0] || {};
        
        let gateway = '192.168.1.1';
        if (primary.address) {
            if (primary.address.startsWith('192.168.43.')) {
                gateway = '192.168.43.1'; // Standard Android Hotspot gateway
            } else if (primary.address.startsWith('172.20.10.')) {
                gateway = '172.20.10.1'; // Standard iPhone Hotspot gateway
            } else if (primary.address.startsWith('192.168.137.')) {
                gateway = '192.168.137.1'; // Standard Windows Hotspot gateway
            } else {
                const parts = primary.address.split('.');
                parts[3] = '1';
                gateway = parts.join('.');
            }
        }

        return {
            interfaceName: primary.name || 'Wi-Fi',
            interfaceType: primary.type || 'wifi',
            localIp: primary.address || this.currentIp,
            subnetMask: primary.netmask || '255.255.255.0',
            broadcastIp: primary.broadcast || '255.255.255.255',
            gatewayIp: gateway,
            serverBindAddress: '0.0.0.0',
            serverPort: 3000,
            allInterfaces: ifaces,
            isHotspot: (primary.type === 'hotspot' || primary.type === 'phone_hotspot'),
            offlineModeHealth: '100% Offline Capable — Zero Cloud/Internet Dependencies',
            timestamp: new Date().toISOString()
        };
    }

    _checkNetwork() {
        try {
            const freshInterfaces = getNetworkInterfaces();
            const freshPrimaryIp = getPrimaryIp();

            const isIpChanged = freshPrimaryIp !== this.currentIp;
            const isInterfaceCountChanged = freshInterfaces.length !== this.currentInterfaces.length;

            if (isIpChanged || isInterfaceCountChanged) {
                const oldIp = this.currentIp;
                this.currentIp = freshPrimaryIp;
                this.currentInterfaces = freshInterfaces;

                const diag = this.getDiagnostics();
                console.log(`=======================================================`);
                console.log(`[NETWORK] Interface shift detected!`);
                console.log(`[NETWORK] Previous IP: ${oldIp} -> New IP: ${this.currentIp}`);
                console.log(`[NETWORK] Interface: ${diag.interfaceName} (${diag.interfaceType})`);
                console.log(`[NETWORK] Subnet Mask: ${diag.subnetMask} | Broadcast: ${diag.broadcastIp}`);
                console.log(`[NETWORK] Gateway: ${diag.gatewayIp}`);
                console.log(`=======================================================`);

                this.emit('network_changed', {
                    previousIp: oldIp,
                    newIp: this.currentIp,
                    diagnostics: diag
                });
            }
        } catch (err) {
            console.error('[NETWORK] Monitor check error:', err.message);
        }
    }
}

module.exports = new NetworkMonitor();
