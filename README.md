docker rm -f my_onion

docker build -t ft_onion .

docker run -d --name my_onion ft_onion

docker logs my_onion

docker exec my_onion cat /var/lib/tor/hidden_service/hostname