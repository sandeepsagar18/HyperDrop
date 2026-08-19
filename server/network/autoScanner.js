const { exec } = require('child_process');
const http = require('http');
const os = require('os');
const { getNetworkInterfaces } = require('./interfaces');

/**
 * Parses OS ARP table to extract connected IP addresses on the local Wi-Fi & Hotspot subnets.
 * Strictly filters out router gateways (.1, .254), multicast (224.x, 239.x), and broadcasts.
 */
function getArpConnectedDevices() {
    return new Promise((resolve) => {
        const cmd = os.platform() === 'win32' ? 'arp -a' : 'arp -n';
        exec(cmd, (err, stdout) => {
            if (err || !stdout) return resolve([]);

            const devices = [];
            const lines = stdout.split('\n');
            const ipRegex = /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/g;

            for (const line of lines) {
                // Look for dynamic entries on the LAN
                if (line.includes('dynamic') || (!line.includes('static') && !line.includes('Interface:') && !line.includes('Internet Address'))) {
                    const match = line.match(ipRegex);
                    if (match && match.length > 0) {
                        const ip = match[0];
                        // Filter out router gateway (.1, .254), broadcast (.255), multicast, and loopback
                        if (
                            !ip.endsWith('.1') &&
                            !ip.endsWith('.254') &&
                            !ip.endsWith('.255') &&
                            !ip.startsWith('224.') &&
                            !ip.startsWith('239.') &&
                            !ip.startsWith('127.') &&
                            !ip.startsWith('255.')
                        ) {
                            devices.push(ip);
                        }
                    }
                }
            }

            resolve([...new Set(devices)]);
        });
    });
}

/**
 * Checks if an IP is actively running HyperDrop
 */
function probeDevice(ip, port = 3000, timeout = 1000) {
    return new Promise((resolve) => {
        const req = http.get(`http://${ip}:${port}/api/status`, { timeout }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(data);
                    if (parsed && parsed.success) {
                        return resolve({ isHyperDrop: true, ip, port, data: parsed });
                    }
                } catch (e) {}
                resolve(null);
            });
        });

        req.on('error', () => resolve(null));
        req.on('timeout', () => {
            req.destroy();
            resolve(null);
        });
    });
}

module.exports = {
    getArpConnectedDevices,
    probeDevice
};
