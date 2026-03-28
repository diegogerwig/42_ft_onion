# Image and container names
IMAGE_NAME = ft_onion
CONTAINER_NAME = my_onion

# Main rule: builds the image and runs the container
all: build run logs 


# Builds the Docker image without using the cache
build:
	docker build --no-cache -t $(IMAGE_NAME) .

# Runs the container in the background
run:
	docker run -d --name $(CONTAINER_NAME) -p 4242:4242 $(IMAGE_NAME)
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

# Tests the SSH connection locally inside the container (Debugging)
test-local:
	@echo "Probando SSH localmente. La contraseña es: password4242"
	ssh -i conf/onion_key -o StrictHostKeyChecking=no onionuser@127.0.0.1 -p 4242

# Stops and removes the container
clean:
	docker rm -f $(CONTAINER_NAME) || true

# Removes the container and the Docker image for a deep clean
fclean: clean
	docker rmi -f $(IMAGE_NAME) || true

# Deep cleans, then rebuilds and runs everything
re: fclean all

# Prevents conflicts if you have files named like these rules
.PHONY: all build run logs onion clean fclean re