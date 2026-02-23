# ============================================================
# Stage 1: Build the picoclaw binary
# ============================================================
FROM golang:1.26.0-alpine AS builder

RUN apk add --no-cache git make bash

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN make build

# ============================================================
# Stage 2: Minimal runtime image
# ============================================================
FROM alpine:3.23

RUN apk add --no-cache ca-certificates tzdata curl bash

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:18790/health || exit 1

COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw

RUN addgroup -g 1000 picoclaw && \
    adduser -D -u 1000 -G picoclaw picoclaw

# Copy template config into the image (does not overwrite runtime config.json)
COPY config/config.example.json /usr/local/share/picoclaw/config.example.json

# Create entrypoint wrapper (no heredoc; safe for BuildKit/Dokploy)
USER root
RUN set -eux; \
  printf '%s\n' \
'#!/bin/sh' \
'set -eu' \
'' \
'CFG_DIR="/home/picoclaw/.picoclaw"' \
'CFG_FILE="$CFG_DIR/config.json"' \
'TPL_FILE="/usr/local/share/picoclaw/config.example.json"' \
'' \
'mkdir -p "$CFG_DIR"' \
'' \
'if [ ! -f "$CFG_FILE" ] && [ -f "$TPL_FILE" ]; then' \
'  cp "$TPL_FILE" "$CFG_FILE"' \
'  chown picoclaw:picoclaw "$CFG_FILE" 2>/dev/null || true' \
'fi' \
'' \
'exec /usr/local/bin/picoclaw "$@"' \
  > /usr/local/bin/picoclaw-entrypoint; \
  chmod +x /usr/local/bin/picoclaw-entrypoint
USER picoclaw

# Keep your onboard step
RUN /usr/local/bin/picoclaw onboard

ENTRYPOINT ["/usr/local/bin/picoclaw-entrypoint"]
CMD ["gateway"]