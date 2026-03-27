# 1. Matamos el contenedor (si quedó alguno por ahí)
docker rm -f my_onion

# 2. Reconstruimos
docker build -t ft_onion .

# 3. Arrancamos
docker run -d --name my_onion ft_onion

# 4. ESPERA 10 SEGUNDOS AQUÍ... y luego miras el log
sleep 10 && docker logs my_onion

https://www.browserling.com/tor-testing