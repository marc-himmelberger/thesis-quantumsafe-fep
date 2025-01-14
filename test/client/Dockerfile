FROM ubuntu:latest

RUN apt update
# For actually using Tor
RUN apt install -y tor nano obfs4proxy
# Dev Dependencies
RUN apt install -y jq curl netcat-openbsd

RUN apt clean
RUN rm -rf /var/lib/apt/lists/*

COPY torrc /etc/tor/torrc

COPY test.sh /test.sh
RUN chmod +x /test.sh

ENTRYPOINT ["/test.sh"]
