#!/bin/bash

mkdir -p /run/sshd

/usr/sbin/sshd

nginx &

su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &

echo "Waiting for the Tor network to bootstrap..."
sleep 10

tail -f /dev/null