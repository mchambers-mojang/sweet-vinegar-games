FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json server.ts ./
RUN npm ci && npm run build

FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
EXPOSE 8080
ENV PORT=8080
CMD ["node", "dist/server.js"]
