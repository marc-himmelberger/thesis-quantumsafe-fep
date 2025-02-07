# Base docker image
FROM debian:stable-slim

# Set to 101 for backward compatibility
ARG UID=101
ARG GID=101

RUN groupadd -g $GID debian-tor
RUN useradd -m -u $UID -g $GID -s /bin/false -d /var/lib/tor debian-tor

# Use Debian backports instead of db.tpo, since db.tpo doesn't yet support armv7 arch
RUN printf "deb http://deb.debian.org/debian stable-backports main\n" >> /etc/apt/sources.list.d/backports.list
RUN apt-get update && apt-get install -y -t stable-backports \
    ca-certificates \
    libcap2-bin \
    tor \
    tor-geoipdb \
    wget \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget https://go.dev/dl/go1.23.6.linux-amd64.tar.gz
RUN tar -C /usr/local -xzf go1.23.6.linux-amd64.tar.gz
ENV PATH="$PATH:/usr/local/go/bin"
RUN GOBIN=/usr/local/bin/ go install github.com/go-delve/delve/cmd/dlv@latest

COPY ./lyrebird-pq-obfs /lyrebird-pq-obfs
RUN chown debian-tor:debian-tor /lyrebird-pq-obfs
RUN chmod 0755 /lyrebird-pq-obfs
# COPY --from=builder /lyrebird-pq-obfs/lyrebird /usr/bin/lyrebird
COPY docker/bridge-debug/wrapper.sh /usr/bin/wrapper.sh
RUN chmod +x /usr/bin/wrapper.sh
# Allow lyrebird to bind to ports < 1024.
# RUN setcap cap_net_bind_service=+ep /usr/bin/lyrebird

# Our torrc is generated at run-time by the script start-tor.sh.
RUN rm /etc/tor/torrc
RUN chown debian-tor:debian-tor /etc/tor
RUN chown debian-tor:debian-tor /var/log/tor

COPY docker/bridge-debug/start-tor.sh /usr/local/bin
RUN chmod 0755 /usr/local/bin/start-tor.sh

COPY docker/bridge-debug/get-bridge-line /usr/local/bin
RUN chmod 0755 /usr/local/bin/get-bridge-line

USER debian-tor

CMD [ "/usr/local/bin/start-tor.sh" ]
