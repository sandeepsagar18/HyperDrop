const os = require('os');

/**
 * Retrieves all active IPv4 network interfaces with friendly categorization
 * for both Same Wi-Fi and Offline Hotspot (No Internet) modes.
 */
function getNetworkInterfaces() {
    const interfaces = os.networkInterfaces();
    const active = [];

    for (const [name, addrs] of Object.entries(interfaces)) {
        for (const addr of addrs) {
            if (addr.family === 'IPv4' && !addr.internal) {
                // Calculate broadcast address if netmask is available
                let broadcast = '255.255.255.255';
                if (addr.netmask) {
                    const ipParts = addr.address.split('.').map(Number);
                    const maskParts = addr.netmask.split('.').map(Number);
                    const bcastParts = ipParts.map((part, i) => (part | (~maskParts[i] & 255)));
                    broadcast = bcastParts.join('.');
                }

                // Determine interface type & friendly label
                const lowerName = name.toLowerCase();
                let type = 'wifi';
                let modeLabel = 'Same Wi-Fi Network';
                let modeDesc = 'Both devices connected to same Home/Office Wi-Fi';
                let icon = 'fa-wifi';

                if (addr.address.startsWith('192.168.137.') || lowerName.includes('local area connection*') || lowerName.includes('wi-fi direct') || lowerName.includes('hotspot')) {
                    type = 'hotspot';
                    modeLabel = 'Offline Laptop Hotspot';
                    modeDesc = 'Turn on Laptop Hotspot, phone connects with Mobile Data OFF';
                    icon = 'fa-tower-broadcast';
                } else if (addr.address.startsWith('192.168.43.') || addr.address.startsWith('172.20.10.')) {
                    type = 'phone_hotspot';
                    modeLabel = 'Offline Phone Hotspot';
                    modeDesc = 'Phone Hotspot active (Mobile Data turned OFF)';
                    icon = 'fa-mobile-screen-button';
                } else if (addr.address.startsWith('192.168.42.') || lowerName.includes('rndis') || lowerName.includes('tethering')) {
                    type = 'usb';
                    modeLabel = 'USB Tethering';
                    modeDesc = 'Connected via direct USB cable';
                    icon = 'fa-usb';
                } else if (lowerName.includes('eth') || lowerName.includes('ethernet') || lowerName.includes('lan')) {
                    type = 'ethernet';
                    modeLabel = 'Ethernet / LAN';
                    modeDesc = 'Wired network connection';
                    icon = 'fa-network-wired';
                }

                active.push({
                    name,
                    address: addr.address,
                    netmask: addr.netmask,
                    broadcast,
                    mac: addr.mac,
                    type,
                    modeLabel,
                    modeDesc,
                    icon
                });
            }
        }
    }

    // Sort to prioritize active connected Wi-Fi first, then other networks
    active.sort((a, b) => {
        const order = { wifi: 1, ethernet: 2, phone_hotspot: 3, hotspot: 4, usb: 5 };
        return (order[a.type] || 10) - (order[b.type] || 10);
    });

    if (active.length === 0) {
        active.push({
            name: 'Loopback',
            address: '127.0.0.1',
            netmask: '255.0.0.0',
            broadcast: '127.255.255.255',
            mac: '00:00:00:00:00:00',
            type: 'loopback',
            modeLabel: 'Localhost',
            modeDesc: 'Local machine only',
            icon: 'fa-laptop'
        });
    }

    return active;
}

/**
 * Returns primary preferred IP address for hosting server
 */
function getPrimaryIp() {
    const ifaces = getNetworkInterfaces();
    // Prioritize active connected Wi-Fi or LAN
    const preferred = ifaces.find(i => i.type === 'wifi' || i.type === 'ethernet' || i.type === 'phone_hotspot') || ifaces[0];
    return preferred.address;
}

module.exports = {
    getNetworkInterfaces,
    getPrimaryIp
};
