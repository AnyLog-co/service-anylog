#!/bin/Makefile
$(info LOADING MAKEFILE)

# Default values
export ANYLOG_TYPE ?=
export TAG         ?= pre-develop

# OpenHorizon configs
export HZN_ORG_ID      ?= myorg
export HZN_LISTEN_IP   ?= 127.0.0.1
export SERVICE_VERSION ?= 1.3.5
export TEST_CONN       ?=

# Detect OS / architecture
export OS      := $(shell uname -s)
export UNAME_M := $(shell uname -m)
export ANYLOG_UID := $(shell id -u)
export ANYLOG_GID := $(shell id -g)

ifeq ($(UNAME_M),x86_64)
	export DOCKER_PLATFORM := linux/amd64
else ifneq (,$(filter $(UNAME_M),aarch64 arm64))
	export DOCKER_PLATFORM := linux/arm64
else
	$(error Unsupported architecture: $(UNAME_M))
endif

# ARCH: prefer hzn if available, otherwise derive from uname
export ARCH := $(shell command -v hzn >/dev/null 2>&1 && hzn architecture || \
	( [ "$(UNAME_M)" = "x86_64" ] && echo "amd64" || echo "arm64" ))

# -------------------
# Defaults in Make
# -------------------
ifneq ($(strip $(ANYLOG_TYPE)),)
    _SINGLE_FILE := docker-makefiles/$(ANYLOG_TYPE)/node_configs.env
    export IMAGE        ?= $(shell grep -m1 '^IMAGE='     "$(_SINGLE_FILE)" | cut -d= -f2- | tr -d '"\r')
    export NODE_NAME    := $(shell grep -m1 '^NODE_NAME=' "$(_SINGLE_FILE)" | cut -d= -f2- | tr -d '"\r')
    export SERVICE_NAME ?= $(NODE_NAME)
else
    $(error Missing configuration file(s) for $(ANYLOG_TYPE))
endif

export CONTAINER_CMD      := $(shell command -v podman >/dev/null 2>&1 && echo "podman" || echo "docker")
export DOCKER_COMPOSE_CMD := $(shell \
    command -v podman-compose  >/dev/null 2>&1 && echo "podman-compose"  || \
    command -v docker-compose  >/dev/null 2>&1 && echo "docker-compose"  || \
    echo "docker compose")
export DOCKER_COMPOSE_FILE := docker-makefiles/docker-compose-files/$(ANYLOG_TYPE)-docker-compose.yaml

# Generated policy files live alongside the .env, inside docker-makefiles/$(ANYLOG_TYPE)/
export POLICY_DIR := docker-makefiles/$(ANYLOG_TYPE)

#========= prep configs =========
all: help

check-configs:
	@if [ "$(IS_MANUAL)" != "true" ] && [ -z "$(ANYLOG_TYPE)" ]; then \
		echo "ERROR: Missing AnyLog type"; \
		exit 1; \
	elif [ "$(IS_MANUAL)" != "true" ] && [ ! -d docker-makefiles/$(ANYLOG_TYPE) ]; then \
		echo "ERROR: Missing directory for ANYLOG_TYPE=$(ANYLOG_TYPE)"; \
		$(MAKE) help; \
		exit 1; \
	fi
	@echo $(IMAGE)

login: ## log into docker hub for AnyLog
	$(CONTAINER_CMD) login docker.io -u anyloguser --password $(ANYLOG_TYPE)

pull: check-configs ## pull image from docker hub
	$(CONTAINER_CMD) pull docker.io/$(IMAGE):$(TAG)

#========= Docker compose =========
dry-run: check-configs ## generate docker-compose.yaml
	@echo "Dry Run ${ANYLOG_TYPE} - ${NODE_NAME}"
	bash docker-makefiles/prep_configs.sh $(ANYLOG_TYPE)
	bash docker-makefiles/build_docker_compose.sh $(ANYLOG_TYPE) $(TAG)

up: dry-run ## start AnyLog instance
	@echo "Deploy AnyLog $(ANYLOG_TYPE)"
	$(DOCKER_COMPOSE_CMD) -f $(DOCKER_COMPOSE_FILE) up -d

down: dry-run ## stop docker container
	@echo "Stop AnyLog Agent - $(ANYLOG_TYPE)"
	$(DOCKER_COMPOSE_CMD) -f $(DOCKER_COMPOSE_FILE) down

clean: dry-run ## stop container and remove volumes
	@echo "Stop AnyLog Agent - $(ANYLOG_TYPE)"
	$(DOCKER_COMPOSE_CMD) -f $(DOCKER_COMPOSE_FILE) down -v

clean-all: dry-run ## stop container, remove volumes and image
	@echo "Stop AnyLog Agent - $(ANYLOG_TYPE)"
	$(DOCKER_COMPOSE_CMD) -f $(DOCKER_COMPOSE_FILE) down -v --rmi all

logs: check-configs ## view logs
	$(CONTAINER_CMD) logs $(NODE_NAME)

logs-f: check-configs ## view logs continuously
	$(CONTAINER_CMD) logs -f $(NODE_NAME)

attach: check-configs ## attach to container
	$(CONTAINER_CMD) attach --detach-keys=ctrl-d $(NODE_NAME)

exec: check-configs ## attach to bash shell
	$(CONTAINER_CMD) exec -it $(NODE_NAME) /bin/bash

#========= Open Horizon commands =========
prep-service: check-configs ## generate service.definition.json, service.policy.json and node.policy.json
	@echo "Open Horizon Dry Run $(ANYLOG_TYPE) - $(NODE_NAME)"
	bash ./docker-makefiles/env2json.sh $(POLICY_DIR) . $(TAG)

full-deploy: publish-service publish-service-policy publish-deployment-policy agent-run ## deploy all services and policies, then start agent

deploy: publish-deployment-policy agent-run ## publish deployment and run agent

publish: publish-service publish-service-policy publish-deployment-policy ## publish services and policies

publish-version: publish-service publish-service-policy ## update version

publish-service: ## publish service
	@echo "=================="
	@echo "PUBLISHING SERVICE"
	@echo "=================="
	@hzn exchange service publish --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) -O -P \
		--json-file=$(POLICY_DIR)/service.definition.json

publish-service-policy: ## publish service policy
	@echo "========================="
	@echo "PUBLISHING SERVICE POLICY"
	@echo "========================="
	@hzn exchange service addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) \
		-f $(POLICY_DIR)/service.policy.json \
		$(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)

publish-deployment-policy: prep-service ## publish deployment policy
	@echo "============================"
	@echo "PUBLISHING DEPLOYMENT POLICY"
	@echo "============================"
	@hzn exchange deployment addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) \
		-f $(POLICY_DIR)/service.deployment.json \
		$(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION)

agent-run: ## start agent
	@echo "================"
	@echo "REGISTERING NODE"
	@echo "================"
	@hzn register --name=hzn-client --policy=$(POLICY_DIR)/node.policy.json
	@watch $(MAKE) hzn-agreement-list

hzn-clean: ## unregister agent(s) from OpenHorizon
	@echo "==================="
	@echo "UN-REGISTERING NODE"
	@echo "==================="
	@hzn unregister -f
	@echo ""

hzn-agreement-list: ## check agreement list
	@hzn agreement list

hzn-logs: ## logs for Docker container when running in OpenHorizon
	@$(CONTAINER_CMD) logs $(CONTAINER_ID)

deploy-check: ## check deployment
	@hzn deploycheck all -t device \
		-B $(POLICY_DIR)/service.deployment.json \
		--service=$(POLICY_DIR)/service.definition.json \
		--service-pol=$(POLICY_DIR)/service.policy.json \
		--node-pol=$(POLICY_DIR)/node.policy.json

#========= testing =========
# test-node: check-configs ## test a node via REST interface
# ifeq ($(TEST_CONN),)
# 	@echo "ERROR: Missing connection information (TEST_CONN)"
# 	@exit 1
# endif
# 	@echo "Test Node against $(TEST_CONN)"
# 	@curl -X GET http://$(TEST_CONN) -H "command: test node" -H "User-Agent: AnyLog/1.23" -w "\n"
#
# test-network: check-configs ## test the network via REST interface
# ifeq ($(TEST_CONN),)
# 	@echo "ERROR: Missing connection information (TEST_CONN)"
# 	@exit 1
# endif
# 	@echo "Test Network against $(TEST_CONN)"
# 	@curl -X GET http://$(TEST_CONN) -H "command: test network" -H "User-Agent: AnyLog/1.23" -w "\n"

#========= validate & help =========
check-vars: ## show all environment variable values
	@echo "IS_MANUAL             Default: false                    Value: $(IS_MANUAL)"
	@echo "ANYLOG_TYPE           Default: generic                  Value: $(ANYLOG_TYPE)"
	@echo "IMAGE                 Default: anylogco/anylog-network  Value: $(IMAGE)"
	@echo "TAG                   Default: pre-develop              Value: $(TAG)"
	@echo "NODE_NAME             Default: anylog-node              Value: $(NODE_NAME)"
	@echo "SERVICE_NAME                                            Value: $(SERVICE_NAME)"
	@echo "SERVICE_VERSION                                         Value: $(SERVICE_VERSION)"
	@echo "ARCH                                                    Value: $(ARCH)"
	@echo "HZN_ORG_ID            Default: myorg                    Value: $(HZN_ORG_ID)"
	@echo "HZN_LISTEN_IP         Default: 127.0.0.1                Value: $(HZN_LISTEN_IP)"
	@echo "CLUSTER_NAME          Default: new-cluster              Value: $(CLUSTER_NAME)"
	@echo "ANYLOG_SERVER_PORT    Default: 32548                    Value: $(ANYLOG_SERVER_PORT)"
	@echo "ANYLOG_REST_PORT      Default: 32549                    Value: $(ANYLOG_REST_PORT)"
	@echo "ANYLOG_BROKER_PORT    Default:                          Value: $(ANYLOG_BROKER_PORT)"
	@echo "LEDGER_CONN           Default: 127.0.0.1:32048          Value: $(LEDGER_CONN)"
	@echo "LICENSE_KEY           Default:                          Value: $(LICENSE_KEY)"
	@echo "TEST_CONN             Default:                          Value: $(TEST_CONN)"

help:
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk -F':|##' '{ printf "  \033[36m%-22s\033[0m %s\n", $$1, $$3 }'
	@echo ""
	@echo "Common variables you can override:"
	@echo "  ANYLOG_TYPE         Type of node to deploy (e.g., generic, master, operator)"
	@echo "  IMAGE               Docker image repo"
	@echo "  TAG                 Docker image tag"
	@echo "  NODE_NAME           Custom name for the container"
	@echo "  CLUSTER_NAME        Cluster operator node is associated with"
	@echo "  ANYLOG_SERVER_PORT  Port for server communication"
	@echo "  ANYLOG_REST_PORT    Port for REST API"
	@echo "  ANYLOG_BROKER_PORT  Optional broker port"
	@echo "  LEDGER_CONN         Master node IP and port"
	@echo "  LICENSE_KEY         AnyLog license key"
	@echo "  TEST_CONN           REST connection info for test-node / test-network"