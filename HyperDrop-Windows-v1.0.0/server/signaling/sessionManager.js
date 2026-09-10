const crypto = require('crypto');

/**
 * RemoteSessionManager
 * Manages ephemeral pairing rooms, 6-character short codes, and WebRTC signaling sessions.
 * NO file data is ever stored on this signaling server.
 */
class RemoteSessionManager {
    constructor(sessionTtlMs = 15 * 60 * 1000) {
        this.sessionTtlMs = sessionTtlMs;
        this.sessions = new Map(); // sessionId -> sessionData
        this.codeToSession = new Map(); // shortCode -> sessionId
        this.cleanupTimer = setInterval(() => this._cleanupStaleSessions(), 60000);
    }

    generateShortCode() {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let code = '';
        for (let i = 0; i < 6; i++) {
            code += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return `HD-${code.substring(0, 3)}${code.substring(3, 6)}`;
    }

    createSession({ hostDeviceId, hostDeviceName, hostDeviceType }) {
        const sessionId = `rem_${crypto.randomBytes(12).toString('hex')}`;
        const shortCode = this.generateShortCode();
        const sessionToken = `hd_sec_${crypto.randomBytes(16).toString('hex')}`;

        const session = {
            sessionId,
            shortCode,
            sessionToken,
            host: {
                deviceId: hostDeviceId,
                deviceName: hostDeviceName || 'Remote Host',
                deviceType: hostDeviceType || 'laptop',
                ws: null
            },
            guest: null,
            createdAt: Date.now(),
            expiresAt: Date.now() + this.sessionTtlMs,
            status: 'waiting' // 'waiting' | 'paired' | 'closed'
        };

        this.sessions.set(sessionId, session);
        this.codeToSession.set(shortCode.replace(/[^A-Z0-9]/gi, '').toUpperCase(), sessionId);
        this.codeToSession.set(shortCode.toUpperCase(), sessionId);

        console.log(`[SIGNALING] Created remote session ${sessionId} with Short Code: ${shortCode}`);
        return session;
    }

    getSession(sessionId) {
        return this.sessions.get(sessionId);
    }

    getSessionByCode(code) {
        if (!code) return null;
        const normalized = code.trim().replace(/[^A-Z0-9]/gi, '').toUpperCase();
        const sessionId = this.codeToSession.get(normalized) || this.codeToSession.get(code.trim().toUpperCase());
        return sessionId ? this.sessions.get(sessionId) : null;
    }

    joinSession({ sessionIdOrCode, guestDeviceId, guestDeviceName, guestDeviceType, guestToken }) {
        let session = this.getSession(sessionIdOrCode) || this.getSessionByCode(sessionIdOrCode);
        if (!session) {
            return { success: false, error: 'Session code not found or expired' };
        }

        if (session.expiresAt < Date.now()) {
            this.closeSession(session.sessionId);
            return { success: false, error: 'Session has expired' };
        }

        // Validate token if provided
        if (guestToken && session.sessionToken !== guestToken) {
            return { success: false, error: 'Invalid session token' };
        }

        session.guest = {
            deviceId: guestDeviceId,
            deviceName: guestDeviceName || 'Remote Guest',
            deviceType: guestDeviceType || 'phone',
            ws: null
        };
        session.status = 'paired';

        console.log(`[SIGNALING] Guest ${guestDeviceName} (${guestDeviceId}) joined session ${session.sessionId} (${session.shortCode})`);
        return { success: true, session };
    }

    closeSession(sessionId) {
        const session = this.sessions.get(sessionId);
        if (session) {
            this.codeToSession.delete(session.shortCode.replace(/[^A-Z0-9]/gi, '').toUpperCase());
            this.codeToSession.delete(session.shortCode.toUpperCase());
            this.sessions.delete(sessionId);
            console.log(`[SIGNALING] Closed remote session ${sessionId}`);
        }
    }

    _cleanupStaleSessions() {
        const now = Date.now();
        for (const [id, session] of this.sessions.entries()) {
            if (session.expiresAt < now) {
                this.closeSession(id);
            }
        }
    }
}

module.exports = new RemoteSessionManager();
