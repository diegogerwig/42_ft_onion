docker rm -f my_onion

docker build -t ft_onion .

docker run -d --name my_onion ft_onion

docker logs my_onion

