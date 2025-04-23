#!/bin/bash

set -eu

TMPDIR=$(mktemp -d /tmp/helm-XXXXXXXX)
trap "rm -rf $TMPDIR" EXIT HUP INT QUIT PIPE TERM

ORG_DIR="$PWD"

cd $TMPDIR

TAG_NAME=$(curl -sL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/helm/helm/releases/latest  | jq -r .tag_name)
curl -sLO https://get.helm.sh/helm-${TAG_NAME}-linux-amd64.tar.gz
tar -zxvf helm-${TAG_NAME}-linux-amd64.tar.gz
mv linux-amd64/helm "$ORG_DIR"
