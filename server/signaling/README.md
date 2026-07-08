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

**Persistent database (local volume):**

```bash
docker run -p 8080:8080 -v signaling-data:/data carom-signaling
```

## Database Persistence (Azure App Service)

The server stores leaderboard data in a SQLite database. On Azure App Service the
container filesystem is **ephemeral** — the database path must be mapped to a
persistent Azure Files share so data survives redeploys.

### Configure an Azure Files mount

1. In the Azure Portal, open your App Service → **Configuration** → **Path mappings**.
2. Click **New Azure Storage Mount** and fill in:
   - **Name**: `data`
   - **Configuration options**: Azure Files
   - **Storage account**: your storage account
   - **Storage container**: your file share (e.g. `signaling-data`)
   - **Mount path**: `/data`
3. Save and restart the App Service.

The container image sets `DB_PATH=/data/vinegar.db` and `SQLITE_JOURNAL_MODE=DELETE`
via the Dockerfile `ENV` declarations, so no extra app settings are needed once the
mount is in place.

> **Why `SQLITE_JOURNAL_MODE=DELETE`?**
> Azure Files shares use SMB, which does not support the `mmap`/shared-memory
> primitives that SQLite's WAL mode requires. Using WAL on a SMB mount can cause
> silent corruption or `database is locked` errors. `DELETE` journal mode is
> compatible with network filesystems.

To override either value, add a `DB_PATH` or `SQLITE_JOURNAL_MODE` app setting.
For example, to store the database in a subdirectory of the share:
`DB_PATH=/data/prod/vinegar.db`

> **Mount validation:** if the server starts and the Azure Files share is not
> attached, the server logs a warning to stderr:
> `[WARNING] "/data" is not a mount point. ...`
> This indicates data will be lost on redeploy. Check the App Service Path Mapping
> configuration if you see this warning.

> **Non-containerised deployments:** when running outside Docker, `DB_PATH` must
> be set explicitly or the server falls back to `/home/data/vinegar.db`.
> Set `SQLITE_JOURNAL_MODE=WAL` for local filesystem paths where WAL is safe.
> **Local override (Docker):** pass `-e DB_PATH=...` and `-e SQLITE_JOURNAL_MODE=...`
> to `docker run` to override paths and journal mode.

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
