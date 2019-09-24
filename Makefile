GIT_HOST = github.com/multicloudlab
PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
GOBIN_DEFAULT := $(GOPATH)/bin
export GOBIN ?= $(GOBIN_DEFAULT)
TESTARGS_DEFAULT := "-v"
export TESTARGS ?= $(TESTARGS_DEFAULT)
PKG := $(shell awk  -F "\"" '/^ignored = / { print $$2 }' Gopkg.toml)
DEST := $(GOPATH)/src/$(GIT_HOST)/$(BASE_DIR)
SOURCES := $(shell find $(DEST) -name '*.go')

HAS_LINT := $(shell command -v golint;)
GOX_PARALLEL ?= 3
TARGETS ?= darwin/amd64 linux/amd64 linux/386 linux/arm linux/arm64 linux/ppc64le
DIST_DIRS         = find * -type d -exec

GOOS ?= $(shell go env GOOS)
VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)
GOFLAGS   :=
TAGS      :=
LDFLAGS   := "-w -s -X 'main.version=${VERSION}'"

# Image URL to use all building/pushing image targets
CONTROLLER_IMG ?= controller

REGISTRY ?= quay.io/ibmcloud

ifneq ("$(realpath $(DEST))", "$(realpath $(PWD))")
	$(error Please run 'make' from $(DEST). Current directory is $(PWD))
endif

all: test build images

############################################################
# work section
############################################################
$(GOBIN):
	echo "create gobin"
	mkdir -p $(GOBIN)

work: $(GOBIN)	

############################################################
# check section
############################################################
check: fmt vet lint

fmt:
	hack/verify-gofmt.sh

lint:
ifndef HAS_LINT
		go get -u golang.org/x/lint/golint
		echo "installing golint"
endif
	hack/verify-golint.sh

vet:
	go vet ./...

############################################################
# test section
############################################################
test: unit functional fmt vet generate_yaml_test 

unit: check
	go test -tags=unit $(shell go list ./...) $(TESTARGS)

############################################################
# build section
############################################################
build: manager clusterctl

manager: check mgr

clusterctl: check cmd

mgr:
	CGO_ENABLED=0 GOOS=$(GOOS) go build \
		-ldflags $(LDFLAGS) \
		-o bin/manager \
		cmd/manager/main.go
cmd:
	CGO_ENABLED=0 GOOS=$(GOOS) go build \
		-ldflags $(LDFLAGS) \
		-o bin/clusterctl \
		cmd/clusterctl/main.go

############################################################
# images section
############################################################
# Build the docker image
controller-image:
	docker build . -f cmd/manager/Dockerfile -t $(REGISTRY)/$(CONTROLLER_IMG):$(VERSION)

push-controller-image:
	docker push $(REGISTRY)/$(CONTROLLER_IMG):$(VERSION)

images: test controller-image
push-images: push-controller-image

build-push-images: images push-images

# quickly get target image
mgr-img: controller-image push-controller-image

############################################################
# clean section
############################################################
clean:
	rm -f bin/manager bin/clusterctl

realclean: clean
	rm -rf vendor
	if [ "$(GOPATH)" = "$(GOPATH_DEFAULT)" ]; then \
		rm -rf $(GOPATH); \
	fi
