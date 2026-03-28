# Image and container names
IMAGE_NAME = ft_onion
CONTAINER_NAME = my_onion

# Main rule: builds the image and runs the container
all: build run logs 

# Generates SSH keys automatically if they don't exist
conf/onion_key:
	@echo "Generating SSH keys..."
	@mkdir -p conf
	@ssh-keygen -t ed25519 -f conf/onion_key -q -N ""

# Builds the Docker image without using the cache
build: conf/onion_key
	docker build --no-cache -t $(IMAGE_NAME) .

# Runs the container in the background
run:
	docker run -d --name $(CONTAINER_NAME) $(IMAGE_NAME)
	@echo "Container started. Wait about 10 seconds and use 'make onion' to see your URL."

# Shows the container logs
logs:
	sleep 10
	docker logs $(CONTAINER_NAME)

# Directly shows the .onion address
onion:
	@echo "======================================="
	@echo "YOUR DARK WEB ADDRESS IS:"
	@docker exec $(CONTAINER_NAME) cat /var/lib/tor/hidden_service/hostname
	@echo "======================================="

# Tests the SSH connection automatically through the Tor network
test-ssh:
	@echo "Testing SSH connection through Tor..."
	@ONION_URL=$$(docker exec $(CONTAINER_NAME) cat /var/lib/tor/hidden_service/hostname) ; \
	ssh -i conf/onion_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="nc -X 5 -x 127.0.0.1:9050 %h %p" -p 4242 onionuser@$$ONION_URL

# Stops and removes the container
clean:
	docker rm -f $(CONTAINER_NAME) || true

# Removes the container and the Docker image for a deep clean
fclean: clean
	docker rmi -f $(IMAGE_NAME) || true
	rm -f conf/onion_key conf/onion_key.pub

# Deep cleans, then rebuilds and runs everything
re: fclean all

# Prevents conflicts if you have files named like these rules
.PHONY: all build run logs onion clean fclean re