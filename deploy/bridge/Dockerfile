FROM swift:6.0-jammy AS builder

WORKDIR /build

COPY Package.swift ./
COPY packages ./packages
COPY apps ./apps
COPY bridge ./bridge

RUN swift build -c release --product SessionBridgeServer

FROM swift:6.0-jammy

WORKDIR /app

RUN useradd -m -u 10001 waspace \
  && mkdir -p /var/lib/waspace \
  && chown -R waspace:waspace /var/lib/waspace

COPY --from=builder /build/.build/release/SessionBridgeServer /usr/local/bin/SessionBridgeServer

ENV WASPACES_BRIDGE_DB_PATH=/var/lib/waspace/bridge-session.sqlite
ENV WASPACES_BRIDGE_API_TOKEN=change-me

EXPOSE 8080

USER waspace

CMD ["SessionBridgeServer", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
