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

# Note: Make sure 'daemon off;' is REMOVED from your nginx.conf 
# so Nginx runs in the background, allowing Tor to run in the foreground.

# Start SSH and Nginx as services, then run Tor in the foreground
CMD service ssh start && service nginx start && su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc"