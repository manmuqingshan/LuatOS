const MESSAGE_TYPES = {
  hello: "hello",
  status: "status",
  log: "log",
  fsRead: "fs.read",
  fsWrite: "fs.write",
  fsList: "fs.list",
  netOpen: "net.open",
  netSend: "net.send",
  netClose: "net.close",
  error: "error",
  ok: "ok"
};

function parseMessage(raw) {
  const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : String(raw);
  const msg = JSON.parse(text);
  if (!msg || typeof msg.type !== "string") {
    throw new Error("message type is required");
  }
  return msg;
}

function buildMessage(type, payload = {}) {
  return JSON.stringify({ type, ...payload });
}

module.exports = {
  MESSAGE_TYPES,
  parseMessage,
  buildMessage
};
