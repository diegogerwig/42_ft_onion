FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
    nginx \
    tor \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash onionuser && \
    echo "onionuser:password4242" | chpasswd

RUN mkdir -p /run/sshd

COPY index.html /var/www/html/index.html
COPY nginx.conf /etc/nginx/nginx.conf
COPY sshd_config /etc/ssh/sshd_config
COPY torrc /etc/tor/torrc

RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

# ¡AQUÍ ESTÁ LA MAGIA! Usamos ';' para que no se bloqueen entre ellos
CMD /usr/sbin/sshd ; nginx ; su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc"