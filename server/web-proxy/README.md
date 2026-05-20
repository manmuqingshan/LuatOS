# LuatOS Web Proxy

Node.js backend for the LuatOS browser simulator.

## Run

```bash
cd server/web-proxy
npm install
npm start
```

The server:

- serves `bsp/web/web/index.html`
- exposes `GET /api/file?path=...`
- exposes `PUT /api/file?path=...`
- opens a WebSocket on `/ws`
- sends COOP/COEP headers required for `SharedArrayBuffer` + pthreads
