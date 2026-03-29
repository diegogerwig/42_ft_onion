IMAGE_NAME = ft_onion
CONTAINER_NAME = my_onion

all: build run logs onion

onion_key:
	@echo "Generating SSH keys..."
	@mkdir -p conf
	@ssh-keygen -t ed25519 -f conf/onion_key -q -N ""
	@chmod 600 conf/onion_key

build: onion_key
	docker build --no-cache -t $(IMAGE_NAME) .

run:
	docker run -d --name $(CONTAINER_NAME) $(IMAGE_NAME)
	@echo "Container started. Wait about 10 seconds and use 'make onion' to see your URL."

logs:
	sleep 10
	docker logs $(CONTAINER_NAME)

onion:
	@echo "=============================================================="
	@echo "YOUR DARK WEB ADDRESS IS:"
	@docker exec $(CONTAINER_NAME) cat /var/lib/tor/hidden_service/hostname
	@echo "=============================================================="

test-ssh-tor:
	@echo "Testing SSH connection through Tor..."
	@cp conf/onion_key /tmp/onion_key_tmp
	@chmod 600 /tmp/onion_key_tmp
	@ONION_URL=$$(docker exec $(CONTAINER_NAME) cat /var/lib/tor/hidden_service/hostname | tr -d '\r\n') ; \
	torsocks ssh -i /tmp/onion_key_tmp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 4242 onionuser@$$ONION_URL
	@rm -f /tmp/onion_key_tmp

test-ssh-local:
	@echo "Testing SSH connection locally inside the container..."
	@docker cp conf/onion_key $(CONTAINER_NAME):/tmp/onion_key_tmp
	@docker exec $(CONTAINER_NAME) chmod 600 /tmp/onion_key_tmp
	@docker exec -it $(CONTAINER_NAME) ssh -i /tmp/onion_key_tmp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 4242 onionuser@127.0.0.1
	@docker exec $(CONTAINER_NAME) rm -f /tmp/onion_key_tmp

clean:
	docker rm -f $(CONTAINER_NAME) || true

fclean: clean
	docker rmi -f $(IMAGE_NAME) || true
	rm -f conf/onion_key conf/onion_key.pub

re: fclean all

.PHONY: all build run logs onion clean fclean re