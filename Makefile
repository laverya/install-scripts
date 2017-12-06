
build:
	docker build -t install-scripts -f deploy/Dockerfile.prod .

dev:
	docker build -t install-scripts-dev .

# shell for running mysql from composer
shell_composer:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL="$(REPLICATED_INSTALL_URL)" \
		-e MYSQL_USER="$(MYSQL_USER)" \
		-e MYSQL_PASS="$(MYSQL_PASSWORD)" \
		-e MYSQL_HOST="$(MYSQL_HOST)" \
		-e MYSQL_PORT="$(MYSQL_PORT)" \
		-e MYSQL_DB="$(MYSQL_DB)" \
		-v "`pwd`":/usr/src/app \
		install-scripts-dev \
		/bin/bash

test:
	python -m pytest -v tests
	./test.sh

run:
	python main.py
