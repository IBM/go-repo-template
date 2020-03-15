# Copyright 2020 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Specify whether this repo is build locally or not, default values is '1';
# If set to 1, then you need to also set 'DOCKER_USERNAME' and 'DOCKER_PASSWORD'
# environment variables before build the repo.
BUILD_LOCALLY ?= 1

# Image URL to use all building/pushing image targets;
# Use your own docker registry and image name for dev/test by overridding the
# IMAGE_REPO, IMAGE_NAME and RELEASE_TAG environment variable.
IMAGE_REPO ?= quay.io/multicloudlab
IMAGE_NAME ?= go-repo-template

# Maximum retry times of pulling image for each platform before makeing multi-arch image
MAX_PULLING_RETRY ?= 10

# Github host to use for checking the source tree;
# Override this variable ue with your own value if you're working on forked repo.
GIT_HOST ?= github.com/IBM

PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
GOBIN_DEFAULT := $(GOPATH)/bin
export GOBIN ?= $(GOBIN_DEFAULT)
TESTARGS_DEFAULT := "-v"
export TESTARGS ?= $(TESTARGS_DEFAULT)
DEST := $(GOPATH)/src/$(GIT_HOST)/$(BASE_DIR)
VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)

LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
    TARGET_OS ?= linux
    XARGS_FLAGS="-r"
else ifeq ($(LOCAL_OS),Darwin)
    TARGET_OS ?= darwin
    XARGS_FLAGS=
else
    $(error "This system's OS $(LOCAL_OS) isn't recognized/supported")
endif

ARCH := $(shell uname -m)
LOCAL_ARCH := "amd64"
ifeq ($(ARCH),x86_64)
    LOCAL_ARCH="amd64"
else ifeq ($(ARCH),ppc64le)
    LOCAL_ARCH="ppc64le"
else ifeq ($(ARCH),s390x)
    LOCAL_ARCH="s390x"
else
    $(error "This system's ARCH $(ARCH) isn't recognized/supported")
endif

all: fmt check test coverage build images

ifeq (,$(wildcard go.mod))
ifneq ("$(realpath $(DEST))", "$(realpath $(PWD))")
    $(error Please run 'make' from $(DEST). Current directory is $(PWD))
endif
endif

include common/Makefile.common.mk

############################################################
# work section
############################################################
$(GOBIN):
	@echo "create gobin"
	@mkdir -p $(GOBIN)

work: $(GOBIN)

############################################################
# format section
############################################################

# All available format: format-go format-python
# Default value will run all formats, override these make target with your requirements:
#    eg: fmt: format-go format-protos
fmt: format-go format-python

############################################################
# check section
############################################################

check: lint

# All available linters: lint-dockerfiles lint-scripts lint-yaml lint-copyright-banner lint-go lint-python lint-helm lint-markdown
# Default value will run all linters, override these make target with your requirements:
#    eg: lint: lint-go lint-yaml
# The MARKDOWN_LINT_WHITELIST variable can be set with comma separated urls you want to whitelist
lint: lint-all

############################################################
# test section
############################################################

test:
	@echo "Running the tests for $(IMAGE_NAME) on $(LOCAL_OS)..."
	@go test $(TESTARGS) ./...

############################################################
# coverage section
############################################################

coverage:
	@common/scripts/codecov.sh $(BUILD_LOCALLY)

############################################################
# build section
############################################################

build:
	@echo "Building the $(IMAGE_NAME) binary for $(LOCAL_OS)..."
	@common/scripts/gobuild.sh build/_output/bin/$(IMAGE_NAME) ./cmd

############################################################
# image section
############################################################

ifeq ($(BUILD_LOCALLY),0)
    export CONFIG_DOCKER_TARGET = config-docker
endif

build-push-image: build-image push-image

build-image: build
	@echo "Building the $(IMAGE_NAME) docker image for $(LOCAL_OS)..."
	@docker build -t $(IMAGE_REPO)/$(IMAGE_NAME)-$(LOCAL_OS):$(VERSION) -f build/Dockerfile-$(LOCAL_OS) .

push-image: $(CONFIG_DOCKER_TARGET) build-image
	@echo "Pushing the $(IMAGE_NAME) docker image for $(LOCAL_OS)..."
	@docker push $(IMAGE_REPO)/$(IMAGE_NAME)-$(LOCAL_OS):$(VERSION)

############################################################
# multiarch-image section
############################################################

pull-image-amd64:
	@echo "Trying to pull the $(IMAGE_NAME) docker image for amd64...""
	@for i in $(seq 1 $(MAX_PULLING_RETRY); do docker pull $(IMAGE_REPO)/$(IMAGE_NAME)-amd64:$(VERSION) && echo "Pull $(IMAGE_REPO)/$(IMAGE_NAME)-amd64:$(VERSION) image" && break; sleep 10; done

pull-image-ppc64le:
	@echo "Trying to pull the $(IMAGE_NAME) docker image for ppc64le...""
	@for i in $(seq 1 $(MAX_PULLING_RETRY); do docker pull $(IMAGE_REPO)/$(IMAGE_NAME)-ppc64le:$(VERSION) && echo "Pull $(IMAGE_REPO)/$(IMAGE_NAME)-ppc64le:$(VERSION) image" && break; sleep 10; done

pull-image-s390x:
	@echo "Trying to pull the $(IMAGE_NAME) docker image for s390x...""
	@for i in $(seq 1 $(MAX_PULLING_RETRY); do docker pull $(IMAGE_REPO)/$(IMAGE_NAME)-s390x:$(VERSION) && echo "Pull $(IMAGE_REPO)/$(IMAGE_NAME)-s390x:$(VERSION) image" && break; sleep 10; done

multiarch-image: pull-image-amd64 pull-image-ppc64le pull-image-s390x
	@curl -L -o /tmp/manifest-tool https://github.com/estesp/manifest-tool/releases/download/v1.0.0/manifest-tool-linux-amd64
	@chmod +x /tmp/manifest-tool
	@/tmp/manifest-tool push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(IMAGE_REPO)/$(IMAGE_NAME)-ARCH:$(VERSION) --target $(IMAGE_REPO)/$(IMAGE_NAME)
	@/tmp/manifest-tool push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(IMAGE_REPO)/$(IMAGE_NAME)-ARCH:$(VERSION) --target $(IMAGE_REPO)/$(IMAGE_NAME):$(VERSION)

############################################################
# clean section
############################################################
clean:
	@rm -rf build/_output

.PHONY: all work fmt check coverage lint test build build-push-image multiarch-image clean
