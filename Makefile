.PHONY: docker docker-push

docker:
	docker build -t rektide/powerdns:latest .

push:
	docker push rektide/powerdns:latest

all: docker
