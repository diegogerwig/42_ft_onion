FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
    nginx \
    tor \
    openssh-server \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for SSH access
RUN useradd -m -s /bin/bash onionuser && \
    echo "onionuser:pwd4242" | chpasswd

# Create the .ssh directory, copy the public key, and set strict permissions
RUN mkdir -p /home/onionuser/.ssh
COPY conf/onion_key.pub /home/onionuser/.ssh/authorized_keys
RUN chown -R onionuser:onionuser /home/onionuser/.ssh && \
    chmod 700 /home/onionuser/.ssh && \
    chmod 600 /home/onionuser/.ssh/authorized_keys    

# Prepare SSH directory and generate host keys
RUN mkdir -p /run/sshd
RUN ssh-keygen -A

COPY conf/index.html /var/www/html/index.html
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/sshd_config /etc/ssh/sshd_config
COPY conf/torrc /etc/tor/torrc

# Set up Tor hidden service directory with strict permissions
RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

COPY src/entrypoint.sh /usr/local/bin/entrypoint.sh

# Fix line endings (in case the file was saved on Windows) and make it executable
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]