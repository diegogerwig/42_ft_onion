#!/bin/bash

mkdir -p /run/sshd

/usr/sbin/sshd

nginx &

su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &

echo "Waiting for the Tor network to bootstrap..."
sleep 10

echo "================================================================"
echo "YOUR DARK WEB ADDRESS (.onion) IS:"
cat /var/lib/tor/hidden_service/hostname
echo "================================================================"

tail -f /dev/null