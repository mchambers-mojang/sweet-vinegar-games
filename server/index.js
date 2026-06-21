// Carom signaling + matchmaking server
// Handles WebRTC SDP/ICE relay and automatic player pairing.

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = parseInt(process.env.PORT || "8080", 10);
const CLOUDFLARE_TURN_KEY_ID = process.env.CLOUDFLARE_TURN_KEY_ID || "";
const CLOUDFLARE_TURN_API_TOKEN = process.env.CLOUDFLARE_TURN_API_TOKEN || "";

// Cache TURN credentials (valid for 24h, refresh every 12h)
let turnCredentialsCache = null;
let turnCredentialsFetchedAt = 0;
const TURN_CACHE_TTL_MS = 12 * 60 * 60 * 1000; // 12 hours

async function getTurnCredentials() {
  if (!CLOUDFLARE_TURN_KEY_ID || !CLOUDFLARE_TURN_API_TOKEN) {
    console.warn("[TURN] No Cloudflare TURN credentials configured, using STUN only");
    return null;
  }

  const now = Date.now();
  if (turnCredentialsCache && (now - turnCredentialsFetchedAt) < TURN_CACHE_TTL_MS) {
    return turnCredentialsCache;
  }

  try {
    const res = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${CLOUDFLARE_TURN_KEY_ID}/credentials/generate`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${CLOUDFLARE_TURN_API_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ttl: 86400 }),
      }
    );

    if (!res.ok) {
      console.error(`[TURN] Cloudflare API error: ${res.status} ${res.statusText}`);
      return turnCredentialsCache; // return stale cache if available
    }

    const data = await res.json();
    turnCredentialsCache = data.iceServers;
    turnCredentialsFetchedAt = now;
    console.log("[TURN] Refreshed Cloudflare TURN credentials");
    return turnCredentialsCache;
  } catch (err) {
    console.error(`[TURN] Failed to fetch credentials: ${err.message}`);
    return turnCredentialsCache; // return stale cache if available
  }
}

// --- Room storage ---
// Each room: { code, host: ws, hostSdp, joiner: ws, ice: { host: [], joiner: [] } }
const rooms = new Map();

// --- Matchmaking queue ---
// Array of { ws, timestamp }
const matchQueue = [];

function generateCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1
  let code = "";
  for (let i = 0; i < 4; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return rooms.has(code) ? generateCode() : code;
}

function send(ws, msg) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

function removeFromQueue(ws) {
  const idx = matchQueue.findIndex((e) => e.ws === ws);
  if (idx !== -1) matchQueue.splice(idx, 1);
}

function cleanupRoomsFor(ws) {
  for (const [code, room] of rooms) {
    if (room.host === ws || room.joiner === ws) {
      // Notify the other peer
      const other = room.host === ws ? room.joiner : room.host;
      if (other && other.readyState === other.OPEN) {
        send(other, { type: "error", message: "Peer disconnected" });
      }
      rooms.delete(code);
    }
  }
}

// --- Matchmaking ---
// When two players are in the queue, pair them: first becomes host, second becomes joiner.
// The server creates a room, tells the host to create an offer, and wires them together.
async function tryMatch() {
  while (matchQueue.length >= 2) {
    const hostEntry = matchQueue.shift();
    const joinerEntry = matchQueue.shift();

    // Verify both are still connected
    if (hostEntry.ws.readyState !== hostEntry.ws.OPEN) {
      if (joinerEntry.ws.readyState === joinerEntry.ws.OPEN) matchQueue.unshift(joinerEntry);
      continue;
    }
    if (joinerEntry.ws.readyState !== joinerEntry.ws.OPEN) {
      matchQueue.unshift(hostEntry);
      continue;
    }

    const code = generateCode();
    const room = {
      code,
      host: hostEntry.ws,
      hostSdp: null,
      joiner: joinerEntry.ws,
      ice: { host: [], joiner: [] },
    };
    rooms.set(code, room);

    // Tag the websockets with their room
    hostEntry.ws._roomCode = code;
    hostEntry.ws._role = "host";
    joinerEntry.ws._roomCode = code;
    joinerEntry.ws._role = "joiner";

    // Fetch TURN credentials to include in matched message
    const iceServers = await getTurnCredentials();

    // Tell the host they've been matched — they should create an RTC offer
    send(hostEntry.ws, { type: "matched", code, role: "host", iceServers });
    // Tell the joiner to wait for the host's offer
    send(joinerEntry.ws, { type: "matched", code, role: "joiner", iceServers });

    console.log(`[Match] Paired ${code}: host + joiner`);
  }
}

// --- Message handling ---
function handleMessage(ws, msg) {
  let data;
  try {
    data = JSON.parse(msg);
  } catch {
    return;
  }

  const type = data.type;

  switch (type) {
    // --- Manual room flow ---
    case "create": {
      // Host creates a room with their SDP offer
      const code = generateCode();
      rooms.set(code, {
        code,
        host: ws,
        hostSdp: data.sdp || null,
        joiner: null,
        ice: { host: [], joiner: [] },
      });
      ws._roomCode = code;
      ws._role = "host";
      send(ws, { type: "room_created", code });
      console.log(`[Room] Created ${code}`);
      break;
    }

    case "join": {
      const code = (data.code || "").toUpperCase();
      const room = rooms.get(code);
      if (!room) {
        send(ws, { type: "error", message: "Room not found" });
        return;
      }
      if (room.joiner) {
        send(ws, { type: "error", message: "Room is full" });
        return;
      }
      room.joiner = ws;
      ws._roomCode = code;
      ws._role = "joiner";
      // Send the host's offer to the joiner
      send(ws, { type: "room_joined", code, sdp: room.hostSdp || "" });
      // Flush any ICE candidates the host sent before joiner connected
      for (const ice of room.ice.host) {
        send(ws, ice);
      }
      console.log(`[Room] Joiner joined ${code}`);
      break;
    }

    case "answer": {
      // Joiner sends their SDP answer — relay to host
      const code = (data.code || ws._roomCode || "").toUpperCase();
      const room = rooms.get(code);
      if (!room) return;
      send(room.host, { type: "peer_joined", sdp: data.sdp || "" });
      // Flush any ICE candidates the joiner sent before answer
      for (const ice of room.ice.joiner) {
        send(room.host, ice);
      }
      break;
    }

    case "ice": {
      const code = (data.code || ws._roomCode || "").toUpperCase();
      const room = rooms.get(code);
      if (!room) return;
      const iceMsg = { type: "ice", candidate: data.candidate };
      if (ws === room.host) {
        if (room.joiner) send(room.joiner, iceMsg);
        else room.ice.host.push(iceMsg);
      } else if (ws === room.joiner) {
        if (room.host) send(room.host, iceMsg);
        else room.ice.joiner.push(iceMsg);
      }
      break;
    }

    // --- Matchmaking flow ---
    case "matchmake": {
      removeFromQueue(ws);
      matchQueue.push({ ws, timestamp: Date.now() });
      send(ws, { type: "queued" });
      console.log(`[Match] Player queued (queue size: ${matchQueue.length})`);
      tryMatch();
      break;
    }

    // Host sends offer after being matched
    case "offer": {
      const code = ws._roomCode;
      const room = rooms.get(code);
      if (!room || ws !== room.host) return;
      room.hostSdp = data.sdp;
      // If joiner is already connected, send them the offer
      if (room.joiner) {
        send(room.joiner, { type: "room_joined", code, sdp: data.sdp || "" });
      }
      break;
    }

    case "cancel_matchmake": {
      removeFromQueue(ws);
      send(ws, { type: "matchmake_cancelled" });
      break;
    }

    default:
      console.log(`[Server] Unknown message type: ${type}`);
  }
}

// --- Server startup ---
const server = http.createServer((req, res) => {
  // Health check endpoint for Azure App Service
  if (req.url === "/" || req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      clients: wss.clients.size,
      rooms: rooms.size,
      queue: matchQueue.length,
      turn_configured: !!(CLOUDFLARE_TURN_KEY_ID && CLOUDFLARE_TURN_API_TOKEN),
      turn_key_id_len: CLOUDFLARE_TURN_KEY_ID.length,
    }));
  } else if (req.url === "/turn-test") {
    getTurnCredentials().then((creds) => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ has_creds: !!creds, count: creds ? creds.length : 0, creds }));
    }).catch((err) => {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: err.message }));
    });
  } else {
    res.writeHead(404);
    res.end();
  }
});

const wss = new WebSocketServer({ server });

wss.on("connection", (ws) => {
  console.log(`[Server] Client connected (total: ${wss.clients.size})`);

  ws.on("message", (msg) => handleMessage(ws, msg.toString()));

  ws.on("close", () => {
    removeFromQueue(ws);
    cleanupRoomsFor(ws);
    console.log(`[Server] Client disconnected (total: ${wss.clients.size})`);
  });

  ws.on("error", (err) => {
    console.error(`[Server] WebSocket error: ${err.message}`);
  });
});

// Prune stale queue entries every 30 seconds
setInterval(() => {
  const now = Date.now();
  const staleMs = 60_000; // 1 minute
  for (let i = matchQueue.length - 1; i >= 0; i--) {
    if (now - matchQueue[i].timestamp > staleMs) {
      const ws = matchQueue[i].ws;
      matchQueue.splice(i, 1);
      send(ws, { type: "error", message: "Matchmaking timed out" });
    }
  }
}, 30_000);

server.listen(PORT, () => {
  console.log(`[Server] Carom signaling + matchmaking server listening on port ${PORT}`);
});
