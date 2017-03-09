#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

RETVAL=0

cmd=build
if [ $# -ne 0 ]; then
    cmd="$1"
fi

GOPATH=$(go env GOPATH)
REPO_ROOT=$GOPATH/src/k8s.io/kubernetes
IMG=hostpath-scheduler

build() {
    pushd $REPO_ROOT
    make WHAT=./plugin/cmd/kube-scheduler
    cd $REPO_ROOT/plugin/deploy/kube-scheduler
    tag=$(git describe --tags --always --dirty)
    cp $REPO_ROOT/_output/local/bin/linux/amd64/kube-scheduler .
    chmod +x kube-scheduler
    docker build -t appscode/$IMG:$tag .
    rm kube-scheduler
    docker push appscode/$IMG:$tag
    popd
}

case "$cmd" in
    build)
        build
        ;;
    *)	(10)
        echo $"Usage: $0 {build}"
        RETVAL=1
esac
exit $RETVAL
