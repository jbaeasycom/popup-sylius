.DEFAULT_GOAL := help

substep = /bin/echo -e "\x1b[33m\#\# $1\x1b[0m"
docker_compose_action = docker-compose -f docker-compose.yml exec $(TTY_OPTION) $1 $2
docker_compose_action_root = docker-compose -f docker-compose.yml exec $(TTY_OPTION) -u root $1 $2
run_sf_command = docker-compose -f docker-compose.yml exec $(TTY_OPTION) php tests/Application/bin/console $1 $2
publish_test_results = export CI_JOB_NAME=$1 && ./ci-tools/send-ci-report-test.sh $2
publish_checker_results = export CI_JOB_NAME=$1 && ./ci-tools/send-ci-report-checker.sh $2 $3
publish_coverage_results = ./ci-tools/send-ci-report-test-coverage.sh $1 $2

RESULT_PATH := results
COVERAGE_HTML := coverage/html
COVERAGE_COV := coverage/raw
RESULT_MERGED_PATH := results-merged

# Defined TTY option globally for docker-compose exec. If you need disable TTY display you can run `make <rule> TTY_OPTION="-T"`
# TODO : prefer a boolean for it ?
TTY_OPTION :=

# Defined option for Symfony test server to run server displaying requests
ifneq ($(DAEMON),false)
	DAEMON_OPTION := --daemon
endif

# Create method except for behat rule to avoid parsing next rules of queue
parse_cmd_args = $(filter-out $@,$(MAKECMDGOALS))

##
## Project setup
##-----------------------------------------------------------------
.PHONY: install start stop clean

install: start ## Install requirements for tests
	$(call docker_compose_action, 'php', mkdir -p tests/Application/var)
	$(call docker_compose_action, 'php', chmod -Rf 777 tests/Application/var)
	$(call docker_compose_action_root, 'php', chmod -Rf 777 tests/Application/public)
	$(call docker_compose_action, 'php', mkdir -p $(RESULT_PATH))
	$(call docker_compose_action, 'php', chmod -R 777 $(RESULT_PATH))
	$(call docker_compose_action, 'php', /usr/bin/composer install --no-scripts)
	$(call docker_compose_action, 'php', php bin/create_node_symlink.php)
	$(call docker_compose_action, 'nodejs', yarn --cwd tests/Application install)
	$(call run_sf_command, doctrine:database:create, --if-not-exists -vvv)
	$(call run_sf_command, doctrine:schema:update, --complete --force --no-interaction -vvv)
	$(call run_sf_command, assets:install, tests/Application/public -vvv)
	#$(call docker_compose_action, 'nodejs', yarn --cwd tests/Application encore dev)
	$(call docker_compose_action, 'nodejs', yarn --cwd tests/Application install)
	-$(call docker_compose_action, 'nodejs', yarn --cwd tests/Application run gulp)
	$(call run_sf_command, cache:warmup, -vvv)
	$(call run_sf_command, sylius:fixtures:load, -n)
	$(call run_sf_command, cache:warmup, -e test -vvv)
	$(call run_sf_command, doctrine:database:create, -e test --if-not-exists -vvv)
	$(call run_sf_command, doctrine:schema:update, --complete --force --no-interaction -e test -vvv)

start:  ## Start the project
	docker-compose up -d
	# Solve 'no space left on device' when launching Symfony Local Web Server
	$(call docker_compose_action_root, 'php', rm -rf /root/.symfony/var)
	# Run server for tests (by default)
	$(call docker_compose_action_root, 'php', symfony serve --no-tls --dir tests/Application/ $(DAEMON_OPTION))
	$(call docker_compose_action_root, 'php', symfony server:list)

stop: ## Stop and clean
	docker-compose kill
	docker-compose rm -v --force

clean: stop ## Clean plugin
	docker-compose down -v
	rm -Rf node_modules vendor .phpunit.result.cache

##
## Assets
##-----------------------------------------------------------------
.PHONY: assets assets-watch

assets: ## Build assets for dev environment
	$(call docker_compose_action, 'nodejs', yarn --cwd tests/Application encore dev)

assets-watch: ## Watch asset during development
	$(call docker_compose_action, 'nodejs', yarn --cwd tests/Application encore watch)

##
## QA
##-----------------------------------------------------------------
.PHONY: validate phpstan psalm phpspec phpunit behat

validate: ## Validate composer.json
	$(call docker_compose_action, 'php', composer validate --ansi --strict)

phpstan: ## phpstan level max
	$(call docker_compose_action, 'php', bin/phpstan analyse -c phpstan.neon -l max src/)

psalm: ## psalm
	$(call docker_compose_action, 'php', bin/psalm)

phpspec: ## phpspec without code coverage
	@$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/phpspec run --ansi -f progress --no-interaction --no-coverage $(call parse_cmd_args))

phpspec-ci: ## phpspec and publish report
	@rm -rf $(RESULT_PATH)/phpspec
	@$(call docker_compose_action, 'php', mkdir -p $(RESULT_PATH)/phpspec)
	@rm -rf $(RESULT_PATH)/phpspec.xml $(COVERAGE_HTML)/phpspec $(COVERAGE_COV)/phpspec
	@$(call substep,"Run PHPSPEC tests")
	-$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/phpspec run --no-interaction --format=junit > $(RESULT_PATH)/phpspec/phpspec.xml)
	@$(call substep,"Publish PHPSPEC results")
	-$(call publish_test_results,"phpspec",$(RESULT_PATH)/phpspec)

phpunit: ## phpunit without code coverage
	@$(call docker_compose_action, 'php', bin/phpunit --colors=always $(call parse_cmd_args))

phpunit-ci: ## phpunit and publish report
	@rm -rf $(RESULT_PATH)/phpunit
	@$(call docker_compose_action, 'php', mkdir -p $(RESULT_PATH)/phpunit)
	@rm -rf $(RESULT_PATH)/phpunit.xml $(COVERAGE_HTML)/phpunit $(COVERAGE_COV)/phpunit
	@$(call substep,"Run PHPUnit tests")
	-$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/phpunit --log-junit $(RESULT_PATH)/phpunit/phpunit.xml)
	@$(call substep,"Publish PHPUnit results")
	-$(call publish_test_results,"phpunit",$(RESULT_PATH)/phpunit)

behat: ## Run behat without code coverage
	$(call docker_compose_action, 'php', vendor/behat/behat/bin/behat --colors --strict -vvv $(call parse_cmd_args))

behat-ci: ## Run behat and publish report
	@rm -rf $(RESULT_PATH)/behat $(COVERAGE_HTML)/behat $(COVERAGE_COV)/behat
	@$(call docker_compose_action, 'php', mkdir -p $(RESULT_PATH)/behat)
	@$(call substep,"Run Behat tests")
	-$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/behat --colors --strict -vvv --no-interaction --format progress --out std --format junit --out $(RESULT_PATH)/behat $(CMD_ARGS))
	@$(call substep,"Publish Behat results")
	-$(call publish_test_results,"behat",$(RESULT_PATH)/behat)

ci: lint validate phpstan psalm phpspec phpunit behat ## Execute github actions tasks

##
## CI Easycom
##-----------------------------------------------------------------
lint: ## Run Lint task
	$(call run_sf_command, lint:twig, src tests/Application/templates tests/Application/themes)
	$(call run_sf_command, lint:yaml, src tests/Application/config)

lint-ci: ## Run Lint task and publish report
	@$(call substep,"Run twig linting")
	-(set -x; $(call run_sf_command, lint:twig, src tests/Application/templates tests/Application/themes >> .lint-ci-output.txt && ([ $$? -eq 0 ] && echo "0" > .lint-ci-status1) || echo "1" > .lint-ci-status1))
	@$(call substep,"Run yaml linting")
	-(set -x; $(call run_sf_command, lint:yaml, src tests/Application/config >> .lint-ci-output.txt && ([ $$? -eq 0 ] && echo "0" > .lint-ci-status2) || echo "1" > .lint-ci-status2))
	@cat .lint-ci-output.txt
	@$(call substep,"Publish lintings results")
	@# Evaluate status from tmp status files and send result to CI publication server
	-$(call publish_checker_results,"lint",$$(/bin/sh -c "if [ -s .lint-ci-status1 ] && [ -s .lint-ci-status2 ]; then cat .lint-ci-status* | grep 1 | uniq | wc -l; else echo 1; fi"), ".lint-ci-output.txt")

analyse: lint ## Checking PHP code (static code analysis, code style)
	@$(call substep,"Run PHPStan analyse")
	$(call docker_compose_action, 'php', bin/phpstan analyse -c phpstan.neon -l max src/)
	@$(call substep,"Run code style analyse")
	$(call docker_compose_action, 'php', bin/ecs check src spec features tests/Behat)
	@$(call substep,"Run composer normalize")
	$(call docker_compose_action, 'php', /usr/bin/composer normalize --dry-run --no-update-lock --no-check-lock)

analyse-fix: ## Fix static analysis issues
	$(call docker_compose_action, 'php', bin/ecs check src spec features tests/Behat --fix)
	$(call docker_compose_action, 'php', /usr/bin/composer normalize --no-update-lock --no-check-lock)

analyse-ci: ## Run PHP analyse task and publish report
	@$(call substep,"Run PHPStan analyse")
	-(set -x; $(call docker_compose_action, 'php', bin/phpstan analyse -c phpstan.neon -l max src/ >> .qa-output.txt && ([ $$? -eq 0 ] && echo "0" > .qa-status1) || echo "1" > .qa-status1))
	@$(call substep,"Run code style analyse")
	-(set -x; $(call docker_compose_action, 'php', bin/ecs check src spec features tests/Behat >> .qa-output.txt && ([ $$? -eq 0 ] && echo "0" > .qa-status2) || echo "1" > .qa-status2))
	@$(call substep,"Run composer normalize")
	-(set -x; $(call docker_compose_action, 'php', /usr/bin/composer normalize --dry-run --no-update-lock --no-check-lock >> .qa-output.txt && ([ $$? -eq 0 ] && echo "0" > .qa-status3) || echo "1" > .qa-status3))
	@cat .qa-output.txt
	@$(call substep,"Publish static analyses results")
	@# Evaluate status from tmp status files and send result to CI publication server
	-$(call publish_checker_results,"static_analysis",$$(/bin/sh -c "if [ -s .qa-status1 ] && [ -s .qa-status2 ] && [ -s .qa-status3 ]; then cat .qa-status* | grep 1 | uniq | wc -l; else echo 1; fi"), ".qa-output.txt")

merge-ci: ## Merge tests coverage files
	@$(call substep,"Merge tests coverage results")
	$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/phpunit-merger coverage $(COVERAGE_COV) --html=coverage-merged/html coverage-merged/all.cov)
	@$(call substep,"Merge tests results")
	$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/phpunit-merger log $(RESULT_PATH)/ $(RESULT_MERGED_PATH)/all.xml)
	@echo Output coverage data to make coverage percentage available on project badge
	@#TODO: better way to do it with phpunit-merger ?
	$(call docker_compose_action, 'php', php -d xdebug.mode=coverage bin/phpcov merge $(COVERAGE_COV)/ --text coverage-merged/result.txt)
	cat coverage-merged/result.txt
	@$(call substep,"Publish tests coverage HTML report")
	$(call publish_coverage_results, "coverage-merged/result.txt", "coverage-merged/html")

#TODO: see to add psalm
easycom-ci: lint-ci analyse-ci phpspec-ci phpunit-ci behat-ci merge-ci ## Execute Easycom gitlab-ci tasks and publish reports


##
## Utilities
##-----------------------------------------------------------------
.PHONY: help

help: ## Show all make tasks (default)
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

sf_command: ## Run Symfony command. Usage : `make sf_command "<symfony:command> --command-parameter"`
	@$(call run_sf_command, $(call parse_cmd_args))
	@# FIXME it tries to run symfony command as make rules

connect: ## Connect to php container to run command manually
	docker-compose exec php sh

-include Makefile.local
