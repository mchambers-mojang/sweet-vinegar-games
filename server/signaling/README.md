# Carom Signaling Server

A lightweight WebSocket signaling server that lets two Carom players exchange WebRTC connection metadata (SDP offers/answers and ICE candidates) via short room codes.

> **Note:** This server is only involved in the initial handshake. Once WebRTC peers connect directly, it is no longer needed.

## Requirements

- Node.js 18+

## Local Development

```bash
cd server/signaling
npm install
npm run dev          # run with ts-node (no build step)
# or
npm run build && npm start
```

The server listens on port **8080** by default. Override with the `PORT` environment variable:

```bash
PORT=3000 npm run dev
```

## Running Tests

```bash
cd server/signaling
npm install
npm test
```

## Docker

**Build:**

```bash
docker build -t carom-signaling server/signaling
```

**Run:**

```bash
docker run -p 8080:8080 carom-signaling
# Override port:
docker run -p 3000:3000 -e PORT=3000 carom-signaling
```

## WebSocket API

All messages are JSON.

### Create a room (Client → Server)

```json
{ "type": "create", "sdp": "<offer SDP string>" }
```

**Response** (to creator):

```json
{ "type": "room_created", "code": "ABCD" }
```

### Join a room (Client → Server)

```json
{ "type": "join", "code": "ABCD" }
```

SDP is optional on join. If omitted, the server registers the joiner and sends back the creator's offer so the joiner can create an answer.

**Response to joiner:**

```json
{ "type": "room_joined", "sdp": "<creator's offer SDP>" }
```

If `sdp` was included in the join message, it is forwarded to the creator immediately as `peer_joined`.

### Send answer SDP (Client → Server)

After receiving `room_joined`, the joiner creates a WebRTC answer and sends it:

```json
{ "type": "answer", "code": "ABCD", "sdp": "<answer SDP string>" }
```

**Response to creator:**

```json
{ "type": "peer_joined", "sdp": "<answer SDP>" }
```

### Relay an ICE candidate (Client → Server)

```json
{ "type": "ice", "code": "ABCD", "candidate": { ... } }
```

The server forwards the candidate to the other peer in the room.

### Error (Server → Client)

```json
{ "type": "error", "message": "Room not found" }
```

## Room Code Behaviour

- 4 uppercase alphanumeric characters; ambiguous characters (0/O, 1/I/L) are excluded.
- Rooms expire after **60 seconds** if no second peer joins.
- The room persists after SDP exchange to allow ICE candidate relay and is cleaned up when either peer disconnects.
- Maximum **100** active rooms; attempts beyond this return an error.
