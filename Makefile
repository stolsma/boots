# Only use the recipes defined in these makefiles
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:
# Delete target files if there's an error
# This avoids a failure to then skip building on next run if the output is created by shell redirection for example
# Not really necessary for now, but just good to have already if it becomes necessary later.
.DELETE_ON_ERROR:
# Treat the whole recipe as a one shell script/invocation instead of one-per-line 
.ONESHELL:
# Use bash instead of plain sh 
SHELL := bash
.SHELLFLAGS := -o pipefail -euc

binary := boots
.PHONY: all ${binary} crosscompile dc gen run test
all: ${binary}

CGO_ENABLED := 0
export CGO_ENABLED

GitRev := $(shell git rev-parse --short HEAD)
crosscompile: boots-linux-386 boots-linux-amd64 boots-linux-arm64 boots-linux-armv6 boots-linux-armv7
boots-linux-386:   FLAGS=GOARCH=386
boots-linux-amd64: FLAGS=GOARCH=amd64
boots-linux-arm64: FLAGS=GOARCH=arm64
boots-linux-armv6: FLAGS=GOARCH=arm GOARM=6
boots-linux-armv7: FLAGS=GOARCH=arm GOARM=7
boots-linux-386 boots-linux-amd64 boots-linux-arm64 boots-linux-armv6 boots-linux-armv7: ${binary}
	${FLAGS} GOOS=linux go build -v -ldflags="-X main.GitRev=${GitRev}" -o $@

# this is quick and its really only for rebuilding when dev'ing, I wish go would
# output deps in make syntax like gcc does... oh well this is good enough
${binary}: $(shell git ls-files | grep -v -e vendor -e '_test.go' | grep '.go$$' ) ipxe/bindata.go
	go build -v -ldflags="-X main.GitRev=${GitRev}"

ifeq ($(origin GOBIN), undefined)
GOBIN := ${PWD}/bin
export GOBIN
endif
ipxe/bindata.go: ipxe/bin/ipxe.efi ipxe/bin/snp-hua.efi ipxe/bin/snp-nolacp.efi ipxe/bin/undionly.kpxe
	go-bindata -pkg ipxe -prefix ipxe -o $@ $^
	gofmt -w $@

include ipxev.mk
ipxeconfigs := $(wildcard ipxe/ipxe/*.h)

ipxe/bin/ipxe.efi: ipxe/ipxe/build/bin-x86_64-efi/ipxe.efi
ipxe/bin/snp-nolacp.efi: ipxe/ipxe/build/bin-arm64-efi/snp.efi
ipxe/bin/undionly.kpxe: ipxe/ipxe/build/bin/undionly.kpxe
ipxe/bin/ipxe.efi ipxe/bin/snp-nolacp.efi ipxe/bin/undionly.kpxe:
	cp $^ $@

ipxe/ipxe/build/${ipxev}.tar.gz: ipxev.mk
	mkdir -p $(@D)
	curl -fL https://github.com/ipxe/ipxe/archive/${ipxev}.tar.gz > $@
	echo "${ipxeh}  $@" | sha512sum -c

# given  t=$(patsubst ipxe/ipxe/build/%,%,$@)
# and   $@=ipxe/ipxe/build/*/*
# t       =                */*
ipxe/ipxe/build/bin-arm64-efi/snp.efi ipxe/ipxe/build/bin-x86_64-efi/ipxe.efi ipxe/ipxe/build/bin/undionly.kpxe: ipxe/ipxe/build/${ipxev}.tar.gz ipxe/ipxe/build.sh ${ipxeconfigs}
	+t=$(patsubst ipxe/ipxe/build/%,%,$@)
	rm -rf $(@D)
	mkdir -p $(@D)
	tar -xzf $< -C $(@D)
	cp ${ipxeconfigs} $(@D)
	cd $(@D) && ../../build.sh $$t ${ipxev}

ifeq ($(CI),drone)
run: ${binary}
	${binary}
test:
	go test -race -coverprofile=coverage.txt -covermode=atomic ${TEST_ARGS} ./...
else
run: ${binary}
	docker-compose up -d --build cacher
	docker-compose up --build boots
test:
	docker-compose up -d --build cacher
endif

vet: # go vet
	go vet ./...

go-test: # go test
	go test -gcflags=-l -coverprofile=cover.out ./...
	go tool cover -func=cover.out
	rm -rf cover.out

goimports: # goimports
	@echo be sure goimports is installed
	goimports -w .

golangci-lint: # golangci-lint 
	@echo be sure golangci-lint is installed: https://golangci-lint.run/usage/install/
	golangci-lint run

.PHONY: validate-local
validate-local: vet go-test goimports golangci-lint # validate-local runs all the same validations and tests that CI run
	
	
