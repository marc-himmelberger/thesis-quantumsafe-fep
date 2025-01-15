FROM ubuntu:latest

RUN apt update
# For actually using Tor
RUN apt install -y tor obfs4proxy
# Dev Dependencies
RUN apt install -y jq curl netcat-openbsd

RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash tor-client

COPY torrc /etc/tor/torrc

COPY test.sh /test.sh
RUN chmod +x /test.sh

ENTRYPOINT ["/test.sh"]
