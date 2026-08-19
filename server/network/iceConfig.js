/**
 * ICE / STUN / TURN Configuration Manager
 * Provides configurable STUN and TURN server credentials from environment variables,
 * with public STUN servers by default for direct WebRTC P2P NAT traversal.
 */

function getIceConfiguration() {
    const iceServers = [];

    // 1. Primary & Secondary STUN Servers (Free, public, no-auth)
    const customStun = process.env.STUN_SERVER;
    if (customStun) {
        iceServers.push({ urls: customStun.split(',') });
    } else {
        iceServers.push({
            urls: [
                'stun:stun.l.google.com:19302',
                'stun:stun1.l.google.com:19302',
                'stun:global.stun.twilio.com:3478'
            ]
        });
    }

    // 2. Optional TURN Relay Server (for strict symmetric NAT traversal)
    const turnServer = process.env.TURN_SERVER;
    const turnUsername = process.env.TURN_USERNAME;
    const turnPassword = process.env.TURN_PASSWORD;

    if (turnServer) {
        const turnConfig = { urls: turnServer.split(',') };
        if (turnUsername) turnConfig.username = turnUsername;
        if (turnPassword) turnConfig.credential = turnPassword;
        iceServers.push(turnConfig);
    }

    return {
        iceServers,
        iceCandidatePoolSize: 10
    };
}

module.exports = { getIceConfiguration };
