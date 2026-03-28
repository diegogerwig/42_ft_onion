FROM debian:bullseye-slim

# Install necessary packages
RUN apt-get update && apt-get install -y \
    nginx \
    tor \
    openssh-server \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for SSH access
RUN useradd -m -s /bin/bash onionuser && \
    echo "onionuser:password4242" | chpasswd

# Prepare SSH directory and generate host keys to prevent silent crashes
RUN mkdir -p /run/sshd
RUN ssh-keygen -A

# Copy configuration files and the static web page from the 'conf' directory
COPY conf/index.html /var/www/html/index.html
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/sshd_config /etc/ssh/sshd_config
COPY conf/torrc /etc/tor/torrc

# Set up Tor hidden service directory with strict permissions
RUN mkdir -p /var/lib/tor/hidden_service && \
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service && \
    chmod 700 /var/lib/tor/hidden_service

# Copy the entrypoint script from the 'src' directory
COPY src/entrypoint.sh /usr/local/bin/entrypoint.sh

# Fix line endings (in case the file was saved on Windows) and make it executable
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

# Run the entrypoint script
CMD ["/usr/local/bin/entrypoint.sh"]