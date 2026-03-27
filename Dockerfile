FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
    nginx \
    tor \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash onionuser && \
    echo "onionuser:password4242" | chpasswd

RUN mkdir -p /run/sshd

RUN ssh-keygen -A

COPY index.html /var/www/html/index.html
COPY nginx.conf /etc/nginx/nginx.conf
COPY sshd_config /etc/ssh/sshd_config
COPY torrc /etc/tor/torrc

RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

RUN echo '#!/bin/bash' > /start.sh && \
    echo '/usr/sbin/sshd' >> /start.sh && \
    echo 'nginx &' >> /start.sh && \
    echo 'su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &' >> /start.sh && \
    echo 'echo "Esperando a la red Tor..."' >> /start.sh && \
    echo 'sleep 10' >> /start.sh && \
    echo 'echo "======================================="' >> /start.sh && \
    echo 'echo "TU DIRECCION EN LA DARK WEB ES:"' >> /start.sh && \
    echo 'cat /var/lib/tor/hidden_service/hostname' >> /start.sh && \
    echo 'echo "======================================="' >> /start.sh && \
    echo 'tail -f /dev/null' >> /start.sh && \
    chmod +x /start.sh

CMD ["/start.sh"]