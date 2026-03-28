#!/bin/bash

# 1. Asegurar que el directorio SSH existe
mkdir -p /run/sshd

# 2. Arrancar SSH
/usr/sbin/sshd

# 3. Arrancar Nginx en segundo plano (el & es VITAL por tu 'daemon off;')
nginx &

# 4. Arrancar Tor en segundo plano
su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &

echo "Waiting for the Tor network to bootstrap..."
sleep 10

echo "================================================================"
echo "YOUR DARK WEB ADDRESS (.onion) IS:"
cat /var/lib/tor/hidden_service/hostname
echo "================================================================"

# Mantener vivo el contenedor
tail -f /dev/null