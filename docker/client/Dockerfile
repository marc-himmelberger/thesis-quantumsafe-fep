# build lyrebird
FROM golang AS builder

RUN apt update && apt install -y astyle cmake gcc ninja-build python3-pytest \
    python3-pytest-xdist unzip xsltproc doxygen graphviz python3-yaml valgrind pkg-config
RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

COPY ./lyrebird /lyrebird
WORKDIR /lyrebird
RUN make build

# Base docker image
FROM ubuntu:latest

# For actually using Tor
RUN apt update && apt install -y tor
# Dev Dependencies
RUN apt update && apt install -y jq curl netcat-openbsd dnsutils

RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

COPY --from=builder /lyrebird/lyrebird /usr/bin/lyrebird

RUN useradd -ms /bin/bash tor-client

COPY docker/client/torrc /etc/tor/torrc

COPY docker/client/test.sh /test.sh
RUN chmod +x /test.sh

ENTRYPOINT ["/test.sh"]
