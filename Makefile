.PHONY: build local push namespaces install charts start-kind stop-kind build-buildx render-charts
TAG?=latest
OWNER?=openfaas
SERVER?=ghcr.io
export DOCKER_CLI_EXPERIMENTAL=enabled

TOOLS_DIR := .tools

GOPATH := $(shell go env GOPATH)
CODEGEN_VERSION := $(shell hack/print-codegen-version.sh)
CODEGEN_PKG := $(GOPATH)/pkg/mod/k8s.io/code-generator@${CODEGEN_VERSION}

all: build-docker

$(TOOLS_DIR)/code-generator.mod: go.mod
	@echo "syncing code-generator tooling version"
	@cd $(TOOLS_DIR) && go mod edit -require "k8s.io/code-generator@${CODEGEN_VERSION}"

${CODEGEN_PKG}: $(TOOLS_DIR)/code-generator.mod
	@echo "(re)installing k8s.io/code-generator-${CODEGEN_VERSION}"
	@cd $(TOOLS_DIR) && go mod download -modfile=code-generator.mod

local:
	CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o faas-netes

build-docker:
	docker build \
	-t $(SERVER)/$(OWNER)/faas-netes:$(TAG) .

.PHONY: build-buildx
build-buildx:
	@echo $(SERVER)/$(OWNER)/faas-netes:$(TAG) && \
	docker buildx create --use --name=multiarch --node=multiarch && \
	docker buildx build \
		--push \
		--platform linux/amd64 \
		--tag $(SERVER)/$(OWNER)/faas-netes:$(TAG) \
		.

.PHONY: build-buildx-all
build-buildx-all:
	@docker buildx create --use --name=multiarch --node=multiarch && \
	docker buildx build \
		--platform linux/amd64,linux/arm/v7,linux/arm64 \
		--output "type=image,push=false" \
		--tag $(SERVER)/$(OWNER)/faas-netes:$(TAG) \
		.

.PHONY: publish-buildx-all
publish-buildx-all:
	@echo  $(SERVER)/$(OWNER)/faas-netes:$(TAG) && \
	docker buildx create --use --name=multiarch --node=multiarch && \
	docker buildx build \
		--platform linux/amd64,linux/arm/v7,linux/arm64 \
		--push=true \
		--tag $(SERVER)/$(OWNER)/faas-netes:$(TAG) \
		.

push:
	docker push $(SERVER)/$(OWNER)/faas-netes:$(TAG)

charts:
	cd chart && helm package openfaas/ && helm package kafka-connector/ && helm package cron-connector/ && helm package nats-connector/ && helm package mqtt-connector/ && helm package pro-builder/
	mv chart/*.tgz docs/
	helm repo index docs --url https://openfaas.github.io/faas-netes/ --merge ./docs/index.yaml
	./contrib/create-static-manifest.sh

render-charts:
	./contrib/create-static-manifest.sh
	./contrib/create-static-manifest.sh ./chart/openfaas ./yaml_arm64 ./chart/openfaas/values-arm64.yaml
	./contrib/create-static-manifest.sh ./chart/openfaas ./yaml_armhf ./chart/openfaas/values-armhf.yaml

start-kind: ## attempt to start a new dev environment
	@./contrib/create_dev.sh

stop-kind: ## attempt to stop the dev environment
	@./contrib/stop_dev.sh

.PHONY: verify-codegen
verify-codegen: ${CODEGEN_PKG}
	./hack/verify-codegen.sh

.PHONY: update-codegen
update-codegen: ${CODEGEN_PKG}
	./hack/update-codegen.sh
