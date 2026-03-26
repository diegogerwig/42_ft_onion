# Use Debian as the base image for stability and ease of setting up SSH/Tor
FROM debian:bullseye-slim

# Update packages and install Nginx, Tor, and OpenSSH Server
RUN apt-get update && apt-get install -y \
    nginx \
    tor \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for SSH access (required to test port 4242)
# We set the username to 'onionuser' and password to 'password4242'
RUN useradd -m -s /bin/bash onionuser && \
    echo "onionuser:password4242" | chpasswd

# Prepare the SSH directory
RUN mkdir -p /run/sshd

# Copy the configuration files and the static web page
COPY index.html /var/www/html/index.html
COPY nginx.conf /etc/nginx/nginx.conf
COPY sshd_config /etc/ssh/sshd_config
COPY torrc /etc/tor/torrc

# Create the hidden service directory and set strict permissions
# Tor will fail to start if these permissions are too open
RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

# Copiamos el script de arranque y le damos permisos de ejecución
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Ejecutamos el script al iniciar el contenedor
CMD ["/usr/local/bin/entrypoint.sh"]