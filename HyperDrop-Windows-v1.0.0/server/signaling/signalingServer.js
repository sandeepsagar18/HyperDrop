const sessionManager = require('./sessionManager');
const { getIceConfiguration } = require('../network/iceConfig');

/**
 * Handles WebRTC signaling messages over WebSocket
 */
function handleSignalingMessage(ws, msg, wss = null) {
    const { type, data } = msg;
    if (!data) return;

    // Helper to find target socket by peerId or session
    const getTargetSocket = (sessionId, targetPeerId) => {
        if (targetPeerId && wss) {
            for (const client of wss.clients) {
                if (client.readyState === 1 && client.peerId === targetPeerId) {
                    return client;
                }
            }
        }
        if (sessionId) {
            const session = sessionManager.getSession(sessionId);
            if (session) {
                return ws === session.host.ws ? (session.guest ? session.guest.ws : null) : session.host.ws;
            }
        }
        return null;
    };

    switch (type) {
        case 'create_remote_session': {
            const session = sessionManager.createSession({
                hostDeviceId: data.deviceId,
                hostDeviceName: data.deviceName,
                hostDeviceType: data.deviceType
            });
            session.host.ws = ws;
            ws.remoteSessionId = session.sessionId;
            ws.isRemoteHost = true;

            ws.send(JSON.stringify({
                type: 'remote_session_created',
                data: {
                    sessionId: session.sessionId,
                    shortCode: session.shortCode,
                    sessionToken: session.sessionToken,
                    iceConfig: getIceConfiguration()
                }
            }));
            break;
        }

        case 'join_remote_session': {
            const result = sessionManager.joinSession({
                sessionIdOrCode: data.sessionIdOrCode,
                guestDeviceId: data.deviceId,
                guestDeviceName: data.deviceName,
                guestDeviceType: data.deviceType,
                guestToken: data.token
            });

            if (!result.success) {
                ws.send(JSON.stringify({
                    type: 'remote_session_error',
                    data: { error: result.error }
                }));
                return;
            }

            const session = result.session;
            session.guest.ws = ws;
            ws.remoteSessionId = session.sessionId;
            ws.isRemoteHost = false;

            const iceConfig = getIceConfiguration();

            // Notify Guest
            ws.send(JSON.stringify({
                type: 'remote_session_joined',
                data: {
                    sessionId: session.sessionId,
                    shortCode: session.shortCode,
                    sessionToken: session.sessionToken,
                    remotePeer: {
                        id: session.host.deviceId,
                        name: session.host.deviceName,
                        deviceType: session.host.deviceType,
                        isHost: true,
                        isRemote: true
                    },
                    iceConfig
                }
            }));

            // Notify Host that Guest has connected
            if (session.host.ws && session.host.ws.readyState === 1) {
                session.host.ws.send(JSON.stringify({
                    type: 'remote_peer_paired',
                    data: {
                        sessionId: session.sessionId,
                        remotePeer: {
                            id: session.guest.deviceId,
                            name: session.guest.deviceName,
                            deviceType: session.guest.deviceType,
                            isHost: false,
                            isRemote: true
                        },
                        iceConfig
                    }
                }));
            }
            break;
        }

        case 'webrtc_offer': {
            const targetWs = getTargetSocket(data.sessionId, data.targetPeerId);
            if (targetWs && targetWs.readyState === 1) {
                console.log(`[WEBRTC] Relaying SDP Offer from ${data.senderId || 'peer'} to target`);
                targetWs.send(JSON.stringify({
                    type: 'webrtc_offer',
                    data: {
                        sessionId: data.sessionId,
                        senderId: data.senderId,
                        senderName: data.senderName,
                        targetPeerId: data.targetPeerId,
                        sdp: data.sdp,
                        iceConfig: getIceConfiguration()
                    }
                }));
            }
            break;
        }

        case 'webrtc_answer': {
            const targetWs = getTargetSocket(data.sessionId, data.targetPeerId);
            if (targetWs && targetWs.readyState === 1) {
                console.log(`[WEBRTC] Relaying SDP Answer from ${data.senderId || 'peer'} to target`);
                targetWs.send(JSON.stringify({
                    type: 'webrtc_answer',
                    data: {
                        sessionId: data.sessionId,
                        senderId: data.senderId,
                        senderName: data.senderName,
                        targetPeerId: data.targetPeerId,
                        sdp: data.sdp
                    }
                }));
            }
            break;
        }

        case 'webrtc_ice_candidate': {
            const targetWs = getTargetSocket(data.sessionId, data.targetPeerId);
            if (targetWs && targetWs.readyState === 1) {
                targetWs.send(JSON.stringify({
                    type: 'webrtc_ice_candidate',
                    data: {
                        sessionId: data.sessionId,
                        senderId: data.senderId,
                        targetPeerId: data.targetPeerId,
                        candidate: data.candidate
                    }
                }));
            }
            break;
        }

        case 'remote_transfer_request': {
            const targetWs = getTargetSocket(data.sessionId, data.targetPeerId);
            if (targetWs && targetWs.readyState === 1) {
                targetWs.send(JSON.stringify({
                    type: 'remote_transfer_request',
                    data: data
                }));
            }
            break;
        }

        case 'remote_transfer_response': {
            const targetWs = getTargetSocket(data.sessionId, data.targetPeerId);
            if (targetWs && targetWs.readyState === 1) {
                targetWs.send(JSON.stringify({
                    type: 'remote_transfer_response',
                    data: data
                }));
            }
            break;
        }
    }
}

function handleSignalingDisconnect(ws) {
    if (ws.remoteSessionId) {
        const session = sessionManager.getSession(ws.remoteSessionId);
        if (session) {
            const otherWs = ws === session.host.ws ? (session.guest ? session.guest.ws : null) : session.host.ws;
            if (otherWs && otherWs.readyState === 1) {
                otherWs.send(JSON.stringify({
                    type: 'remote_peer_disconnected',
                    data: { sessionId: ws.remoteSessionId }
                }));
            }
            sessionManager.closeSession(ws.remoteSessionId);
        }
    }
}

module.exports = {
    handleSignalingMessage,
    handleSignalingDisconnect
};
