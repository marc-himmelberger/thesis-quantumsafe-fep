# build lyrebird
FROM golang AS builder

RUN apt update && apt install -y astyle cmake gcc ninja-build python3-pytest \
    python3-pytest-xdist unzip xsltproc doxygen graphviz python3-yaml valgrind pkg-config
RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

COPY ./lyrebird /lyrebird
WORKDIR /lyrebird
RUN rm -rf liboqs liboqs-go
RUN make liboqs-go
RUN make build

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
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /lyrebird/lyrebird /usr/bin/lyrebird
COPY docker/bridge/wrapper.sh /usr/bin/wrapper.sh
RUN chmod +x /usr/bin/wrapper.sh
# Allow lyrebird to bind to ports < 1024.
RUN setcap cap_net_bind_service=+ep /usr/bin/lyrebird

# Our torrc is generated at run-time by the script start-tor.sh.
RUN rm /etc/tor/torrc
RUN chown debian-tor:debian-tor /etc/tor
RUN chown debian-tor:debian-tor /var/log/tor

COPY docker/bridge/start-tor.sh /usr/local/bin
RUN chmod 0755 /usr/local/bin/start-tor.sh

COPY docker/bridge/get-bridge-line /usr/local/bin
RUN chmod 0755 /usr/local/bin/get-bridge-line

USER debian-tor

CMD [ "/usr/local/bin/start-tor.sh" ]
