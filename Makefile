.SILENT:

# Removes all files in dev
clean-development-old:
	rm -rf command

create-command-main:
	chmod +x scripts/generate-command.sh
	./scripts/generate-command.sh

## Installs a development environment
install: clean-development-old create-command-main

run-dev:
	@cd command; \
	go build -v -o go-wsh-example
	@./command/go-wsh-example

