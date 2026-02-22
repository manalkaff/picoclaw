# ============================================================
# Stage 1: Build the picoclaw binary
# ============================================================
FROM golang:1.26.0-alpine AS builder

RUN apk add --no-cache git make

WORKDIR /src

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN make build

# ============================================================
# Stage 2: Minimal runtime image
# ============================================================
FROM alpine:3.23

RUN apk add --no-cache ca-certificates tzdata curl

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:18790/health || exit 1

# Copy binary
COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw

# Create non-root user and group
RUN addgroup -g 1000 picoclaw && \
    adduser -D -u 1000 -G picoclaw picoclaw

# --- NEW: add a default config template into the image ---
# This does NOT create config.json; it's just a template we can copy from.
COPY config/config.example.json /usr/local/share/picoclaw/config.example.json

# --- NEW: entrypoint wrapper to copy config.json if missing (never overwrite) ---
# Use root to install the script
USER root
RUN set -eux; \
    cat > /usr/local/bin/picoclaw-entrypoint <<'SH'; \
#!/bin/sh
set -eu

CFG_DIR="/home/picoclaw/.picoclaw"
CFG_FILE="$CFG_DIR/config.json"
TPL_FILE="/usr/local/share/picoclaw/config.example.json"

# Ensure base dir exists (in case onboard hasn't run yet or volume is empty)
mkdir -p "$CFG_DIR"

# If config.json doesn't exist, copy from template (do NOT overwrite)
if [ ! -f "$CFG_FILE" ] && [ -f "$TPL_FILE" ]; then
  cp "$TPL_FILE" "$CFG_FILE"
  chown picoclaw:picoclaw "$CFG_FILE" || true
fi

# Hand off to the real command
exec /usr/local/bin/picoclaw "$@"
SH
    chmod +x /usr/local/bin/picoclaw-entrypoint; \
    chown root:root /usr/local/bin/picoclaw-entrypoint

# Switch back to non-root
USER picoclaw

# Run onboard to create initial directories/config (kept as you had)
# If onboard already creates config.json, the entrypoint will do nothing.
RUN /usr/local/bin/picoclaw onboard

ENTRYPOINT ["/usr/local/bin/picoclaw-entrypoint"]
CMD ["gateway"]