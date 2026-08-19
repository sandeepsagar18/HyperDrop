const localtunnel = require('localtunnel');
const EventEmitter = require('events');

/**
 * TunnelManager
 * Creates a free, zero-config public HTTPS tunnel so phones on 4G/5G mobile data
 * can open HyperDrop and scan the Remote QR code from anywhere in the world.
 */
class TunnelManager extends EventEmitter {
    constructor(port = 3000) {
        super();
        this.port = port;
        this.tunnel = null;
        this.publicUrl = null;
        this.isStarting = false;
    }

    async startTunnel() {
        if (this.tunnel && this.publicUrl) {
            return { success: true, publicUrl: this.publicUrl };
        }

        if (this.isStarting) {
            // Wait for existing start attempt
            return new Promise((resolve) => {
                const interval = setInterval(() => {
                    if (this.publicUrl) {
                        clearInterval(interval);
                        resolve({ success: true, publicUrl: this.publicUrl });
                    }
                }, 400);
            });
        }

        this.isStarting = true;
        console.log(`[TUNNEL] Creating free public HTTPS tunnel for port ${this.port}...`);

        try {
            const subdomain = `hyperdrop-${Math.random().toString(36).substring(2, 7)}`;
            this.tunnel = await localtunnel({
                port: this.port,
                subdomain
            });

            this.publicUrl = this.tunnel.url;
            this.isStarting = false;

            console.log(`=======================================================`);
            console.log(`🌐 Public Remote Internet Tunnel ACTIVE:`);
            console.log(`👉 ${this.publicUrl}`);
            console.log(`=======================================================`);

            this.tunnel.on('close', () => {
                console.log('[TUNNEL] Public tunnel closed.');
                this.publicUrl = null;
                this.tunnel = null;
                this.emit('tunnel_closed');
            });

            this.tunnel.on('error', (err) => {
                console.warn('[TUNNEL] Warning:', err.message);
            });

            this.emit('tunnel_ready', { publicUrl: this.publicUrl });
            return { success: true, publicUrl: this.publicUrl };

        } catch (err) {
            this.isStarting = false;
            console.error('[TUNNEL] Failed to start public tunnel:', err.message);
            return { success: false, error: err.message };
        }
    }

    async stopTunnel() {
        if (this.tunnel) {
            this.tunnel.close();
            this.tunnel = null;
            this.publicUrl = null;
            console.log('[TUNNEL] Stopped public tunnel.');
        }
        return { success: true };
    }

    getStatus() {
        return {
            active: !!this.publicUrl,
            publicUrl: this.publicUrl
        };
    }
}

module.exports = new TunnelManager(process.env.PORT || 3000);
