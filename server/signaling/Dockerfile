FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json server.ts db.ts ./
RUN npm ci && npm run build

FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN apk add --no-cache --virtual .build-deps python3 make g++ \
    && npm ci --omit=dev \
    && apk del .build-deps
COPY --from=builder /app/dist ./dist
EXPOSE 8080
ENV PORT=8080
ENV DB_PATH=/data/vinegar.db
# Azure Files uses SMB, which lacks the mmap/shared-memory primitives that WAL requires.
# DELETE journal mode is safe on network filesystems.
ENV SQLITE_JOURNAL_MODE=DELETE
VOLUME ["/data"]
CMD ["node", "dist/server.js"]
