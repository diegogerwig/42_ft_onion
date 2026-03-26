#!/bin/bash

# Asegurarse de que los directorios necesarios existan (por si acaso)
mkdir -p /run/sshd
mkdir -p /var/log/tor
chown debian-tor:debian-tor /var/log/tor

# Iniciar SSH en segundo plano
/usr/sbin/sshd

# Iniciar Nginx en segundo plano
nginx

# Iniciar Tor ejecutándolo como el usuario 'debian-tor' en segundo plano
su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc > /var/log/tor/tor.log 2>&1 &"

# Esperar unos segundos para que Tor genere el hostname
sleep 5

# Imprimir la dirección .onion en los logs del contenedor para que la veas fácilmente
echo "================================================================"
echo "Tu dirección .onion es:"
cat /var/lib/tor/hidden_service/hostname
echo "================================================================"

# Mantener el contenedor vivo leyendo los logs de Tor indefinidamente
tail -f /var/log/tor/tor.log