#!/usr/bin/env node

/**
 * Claude Code for Home Assistant - Image Upload Service
 *
 * Lightweight Express server that handles image uploads from browser paste/drag-drop.
 * Designed for resource-constrained environments (Raspberry Pi).
 *
 * Features:
 * - Serves custom HTML interface with embedded ttyd terminal
 * - Handles image uploads via POST /upload
 * - Saves images to /data/images (persistent storage)
 * - Returns file paths for use with Claude CLI
 * - ARM-compatible (no native dependencies)
 */

const express = require('express');
const http = require('http');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = process.env.IMAGE_SERVICE_PORT || 7680;
const TTYD_PORT = process.env.TTYD_PORT || 7681;
const UPLOAD_DIR = process.env.UPLOAD_DIR || '/data/images';

// Defense in depth: this service must bind 0.0.0.0 so Home Assistant ingress can
// reach it over the internal Supervisor network, but nothing else on that network
// should. Enforcement is by TCP peer address, per the HA add-on developer docs:
// ingress requests always originate from Home Assistant's ingress gateway
// (172.30.32.2), and add-ons must only accept ingress traffic from that address.
// Unlike the X-Ingress-Path / X-Hass-Source headers (which any direct caller can
// forge), the peer address of an established TCP connection is not attacker-
// controlled. Loopback is also trusted so in-container callers (health checks,
// `docker exec` debugging) keep working. Set ENFORCE_INGRESS=0 to disable — e.g.
// for local testing outside HA, where requests arrive from the container's
// bridge gateway instead.
const ENFORCE_INGRESS = process.env.ENFORCE_INGRESS !== '0';
const INGRESS_GATEWAY = '172.30.32.2';

function isTrustedPeer(req) {
    const raw = req.socket.remoteAddress || '';
    const addr = raw.startsWith('::ffff:') ? raw.slice(7) : raw; // IPv4-mapped IPv6
    return addr === INGRESS_GATEWAY || addr === '127.0.0.1' || addr === '::1';
}

// Ensure upload directory exists
if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true, mode: 0o755 });
    console.log(`Created upload directory: ${UPLOAD_DIR}`);
}

// Configure multer for image uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, UPLOAD_DIR);
    },
    filename: (req, file, cb) => {
        const timestamp = Date.now();
        const ext = path.extname(file.originalname) || '.png';
        const filename = `pasted-${timestamp}${ext}`;
        cb(null, filename);
    }
});

const upload = multer({
    storage: storage,
    limits: {
        fileSize: 10 * 1024 * 1024 // 10MB max file size
    },
    fileFilter: (req, file, cb) => {
        // Accept images only
        const allowedMimes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml'];
        if (allowedMimes.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error('Only image files are allowed'));
        }
    }
});

// API routes MUST come before static files middleware
// Otherwise static middleware will intercept API requests

// Health check endpoint — registered BEFORE the ingress guard so the container
// health check / CI smoke test can poll it without coming through ingress.
app.get('/health', (req, res) => {
    res.json({ status: 'ok', uploadDir: UPLOAD_DIR });
});

// Ingress-origin guard (see ENFORCE_INGRESS above). Express runs middleware in
// registration order, so routes above this point (only /health) are exempt by
// construction; everything below requires a trusted peer.
if (ENFORCE_INGRESS) {
    app.use((req, res, next) => {
        if (isTrustedPeer(req)) {
            return next();
        }
        res.status(403).json({
            error: 'Direct access is not allowed. Use the Home Assistant ingress panel.'
        });
    });
}

// Provide ttyd port to frontend
app.get('/config', (req, res) => {
    res.json({
        ttydPort: TTYD_PORT,
        uploadDir: UPLOAD_DIR
    });
});

// Image upload endpoint
app.post('/upload', upload.single('image'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No image file provided' });
    }

    const filePath = path.join(UPLOAD_DIR, req.file.filename);
    console.log(`Image uploaded: ${filePath} (${(req.file.size / 1024).toFixed(2)} KB)`);

    res.json({
        success: true,
        path: filePath,
        filename: req.file.filename,
        size: req.file.size
    });
});

// Proxy endpoint for ttyd terminal
// This allows ttyd to work through Home Assistant ingress
// Handles both HTTP and WebSocket connections
app.use('/terminal', createProxyMiddleware({
    target: `http://localhost:${TTYD_PORT}`,
    changeOrigin: true,
    ws: true, // Enable WebSocket proxying
    pathRewrite: {
        '^/terminal': '' // Remove /terminal prefix when forwarding
    },
    onError: (err, req, res) => {
        console.error('Proxy error:', err.message);
        // res may be a raw socket (WebSocket) instead of an Express response
        if (typeof res.status === 'function') {
            res.status(502).send('Failed to connect to terminal');
        } else if (typeof res.end === 'function') {
            res.end();
        }
    },
    logLevel: 'warn'
}));

// Serve static files (HTML interface) - MUST be after API routes
app.use(express.static(path.join(__dirname, 'public')));

// Multer error handling middleware
app.use((err, req, res, next) => {
    if (err instanceof multer.MulterError) {
        console.error('Multer error:', err.message);
        return res.status(400).json({
            success: false,
            error: `Upload error: ${err.message}`
        });
    }

    if (err) {
        console.error('Error:', err.message);
        return res.status(500).json({
            success: false,
            error: err.message
        });
    }

    next();
});

// Create HTTP server and start listening
const server = http.createServer(app);

// WebSocket upgrades (the ttyd terminal) bypass the Express middleware chain —
// they are handled on the server's 'upgrade' event by http-proxy-middleware. This
// listener is registered first, so it gates non-ingress upgrade attempts before
// the proxy can forward them to ttyd. Rejections answer with a 403 and log the
// peer, rather than silently dropping the socket — otherwise a blocked upgrade
// presents as an endlessly reconnecting blank terminal with nothing in the log.
server.on('upgrade', (req, socket) => {
    if (ENFORCE_INGRESS && !isTrustedPeer(req)) {
        console.warn(`Rejected WebSocket upgrade from untrusted peer ${req.socket.remoteAddress} (${req.url})`);
        socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
        socket.destroy();
    }
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`Claude Code Image Service running on port ${PORT}`);
    console.log(`Upload directory: ${UPLOAD_DIR}`);
    console.log(`ttyd terminal on port: ${TTYD_PORT}`);
    console.log(`Terminal proxy available at /terminal/`);
});
