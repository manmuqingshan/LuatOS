const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");
const { MESSAGE_TYPES, parseMessage, buildMessage } = require("./protocol");

const repoRoot = path.resolve(__dirname, "../../../");
const webRoot = path.join(repoRoot, "bsp", "web", "web");
const storageRoot = path.join(__dirname, "..", "storage");

fs.mkdirSync(storageRoot, { recursive: true });

const contentTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "application/javascript; charset=utf-8"],
  [".wasm", "application/wasm"],
  [".css", "text/css; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".png", "image/png"]
]);

function securityHeaders(res) {
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
  res.setHeader("Access-Control-Allow-Origin", "*");
}

function safeStoragePath(requestPath) {
  const normalized = requestPath.replace(/^\/+/, "");
  const resolved = path.resolve(storageRoot, normalized);
  if (!resolved.startsWith(storageRoot + path.sep) && resolved !== storageRoot) {
    throw new Error("invalid storage path");
  }
  return resolved;
}

async function readRequestBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

const server = http.createServer(async (req, res) => {
  securityHeaders(res);

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, "http://127.0.0.1");
  if (url.pathname === "/api/file") {
    const rel = url.searchParams.get("path");
    if (!rel) {
      res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ error: "path is required" }));
      return;
    }

    try {
      const filePath = safeStoragePath(rel);
      if (req.method === "GET") {
        const data = await fs.promises.readFile(filePath);
        res.writeHead(200, { "Content-Type": "application/octet-stream" });
        res.end(data);
        return;
      }
      if (req.method === "PUT") {
        const body = await readRequestBody(req);
        await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
        await fs.promises.writeFile(filePath, body);
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: true }));
        return;
      }
      res.writeHead(405, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ error: "method not allowed" }));
      return;
    } catch (error) {
      res.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ error: error.message }));
      return;
    }
  }

  const rel = url.pathname === "/" ? "/index.html" : url.pathname;
  const filePath = path.join(webRoot, rel);
  const normalized = path.resolve(filePath);
  if (!normalized.startsWith(webRoot + path.sep) && normalized !== path.join(webRoot, "index.html")) {
    res.writeHead(403);
    res.end("forbidden");
    return;
  }

  try {
    const data = await fs.promises.readFile(normalized);
    const type = contentTypes.get(path.extname(normalized).toLowerCase()) || "application/octet-stream";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  } catch (error) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("not found");
  }
});

const wss = new WebSocketServer({ server, path: "/ws" });

wss.on("connection", (socket) => {
  socket.send(buildMessage(MESSAGE_TYPES.hello, {
    backend: "node",
    storage: "/api/file"
  }));

  socket.on("message", async (raw) => {
    try {
      const msg = parseMessage(raw);
      switch (msg.type) {
        case MESSAGE_TYPES.hello:
          socket.send(buildMessage(MESSAGE_TYPES.ok, { message: "hello" }));
          break;
        case MESSAGE_TYPES.fsRead: {
          const filePath = safeStoragePath(msg.path || "");
          const data = await fs.promises.readFile(filePath, "utf8");
          socket.send(buildMessage(MESSAGE_TYPES.ok, { type: MESSAGE_TYPES.fsRead, path: msg.path, data }));
          break;
        }
        case MESSAGE_TYPES.fsWrite: {
          const filePath = safeStoragePath(msg.path || "");
          await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
          await fs.promises.writeFile(filePath, msg.data ?? "", "utf8");
          socket.send(buildMessage(MESSAGE_TYPES.ok, { type: MESSAGE_TYPES.fsWrite, path: msg.path }));
          break;
        }
        case MESSAGE_TYPES.netOpen:
        case MESSAGE_TYPES.netSend:
        case MESSAGE_TYPES.netClose:
          socket.send(buildMessage(MESSAGE_TYPES.error, {
            message: "network proxy is scaffolded but not wired to the wasm client yet"
          }));
          break;
        default:
          socket.send(buildMessage(MESSAGE_TYPES.error, { message: `unknown type: ${msg.type}` }));
          break;
      }
    } catch (error) {
      socket.send(buildMessage(MESSAGE_TYPES.error, { message: error.message }));
    }
  });
});

const port = Number(process.env.PORT || 8080);
server.listen(port, () => {
  console.log(`LuatOS web proxy listening on http://127.0.0.1:${port}`);
  console.log(`Serving browser shell from ${webRoot}`);
  console.log(`Storage root: ${storageRoot}`);
});
