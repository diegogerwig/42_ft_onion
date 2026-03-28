#!/bin/bash

# Start SSH daemon in the background
/usr/sbin/sshd

# Start Nginx in the background
nginx &

# Start Tor as the 'debian-tor' user in the background
su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &

echo "Waiting for the Tor network to bootstrap..."
sleep 10

echo "================================================================"
echo "YOUR DARK WEB ADDRESS (.onion) IS:"
cat /var/lib/tor/hidden_service/hostname
echo "================================================================"

# Keep the container alive indefinitely
tail -f /dev/null