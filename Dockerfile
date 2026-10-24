ARG GOLANG_VERSION="1.27"

FROM golang:${GOLANG_VERSION}-trixie AS build-stage

WORKDIR /app

RUN mkdir /dist

ENV CGO_ENABLED=0

RUN go install github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login@latest
RUN go install github.com/a8m/envsubst/cmd/envsubst@v1.4.3
RUN go install github.com/babs/ecr-repo-creator@latest
RUN go install github.com/babs/ecr-prime@v1.0.0
RUN go install github.com/regclient/regclient/cmd/regctl@latest
RUN go install github.com/regclient/regclient/cmd/regsync@latest
RUN go install github.com/regclient/regclient/cmd/regbot@latest
RUN go install github.com/google/go-containerregistry/cmd/crane@main

# *_COMMIT = the tag's commit; the build fails if it drifts from what the Go proxy reports for *_VERSION.
# yq has no commit ldflag upstream.
ARG YQ_VERSION="v4.54.1"
ARG ORAS_VERSION="v1.3.5"
ARG ORAS_COMMIT="d6e7b583b9afc7fa3798de77181c53c94418d727"
ARG MANIFEST_TOOL_VERSION="v2.2.2"
ARG MANIFEST_TOOL_COMMIT="b2e25427f2d1c4af2c52249eefa1afa58f662487"
ARG HELM_VERSION="v4.3.1"
ARG HELM_COMMIT="c0d08d0d6d9424d4a14febb5e8a3e51b0dd00dff"
# -X restores the metadata upstream's release builds inject; module-mode go install has no VCS info.
RUN go install -trimpath -ldflags "-s -w" github.com/mikefarah/yq/v4@${YQ_VERSION}
RUN go mod download -json oras.land/oras@${ORAS_VERSION} | grep -qF "\"Hash\": \"${ORAS_COMMIT}\"" \
    && go install -trimpath -ldflags "-s -w -X oras.land/oras/internal/version.GitCommit=${ORAS_COMMIT} -X oras.land/oras/internal/version.GitTreeState=clean" oras.land/oras/cmd/oras@${ORAS_VERSION}
RUN go mod download -json github.com/estesp/manifest-tool/v2@${MANIFEST_TOOL_VERSION} | grep -qF "\"Hash\": \"${MANIFEST_TOOL_COMMIT}\"" \
    && go install -trimpath -ldflags "-s -w -X main.version=${MANIFEST_TOOL_VERSION#v} -X main.gitCommit=${MANIFEST_TOOL_COMMIT}" github.com/estesp/manifest-tool/v2/cmd/manifest-tool@${MANIFEST_TOOL_VERSION}
RUN go mod download -json helm.sh/helm/v4@${HELM_VERSION} | grep -qF "\"Hash\": \"${HELM_COMMIT}\"" \
    && go install -trimpath -ldflags "-s -w -X helm.sh/helm/v4/internal/version.version=${HELM_VERSION} -X helm.sh/helm/v4/internal/version.gitCommit=${HELM_COMMIT} -X helm.sh/helm/v4/internal/version.gitTreeState=clean" helm.sh/helm/v4/cmd/helm@${HELM_VERSION}

COPY --from=ghcr.io/jqlang/jq /jq /dist/
COPY --from=ghcr.io/babs/skopeo-static:1 /usr/local/bin/skopeo /dist/

RUN set -eu \
    && git clone https://github.com/opencontainers/umoci $GOPATH/src/github.com/opencontainers/umoci \
    && cd $GOPATH/src/github.com/opencontainers/umoci && make \
    && mv umoci /dist/

RUN set -ue \
    && cp /go/bin/envsubst \
        /go/bin/ecr-repo-creator \
        /go/bin/ecr-prime \
        /go/bin/docker-credential-ecr-login \
        /go/bin/regctl \
        /go/bin/regsync \
        /go/bin/regbot \
        /go/bin/crane \
        /go/bin/yq \
        /go/bin/oras \
        /go/bin/manifest-tool \
        /go/bin/helm \
        /dist \
    && chmod +rx /dist/*

RUN ls -alh /dist

FROM debian:trixie-slim AS final-stage

RUN set -e \
    && useradd -md /app app \
    && apt update \
    && apt install -y curl nginx-light \
    && sed -ri '/^user.+;$/d' /etc/nginx/nginx.conf \
    && sed -i '/try_files $uri $uri\/ =404/a autoindex on;' /etc/nginx/sites-enabled/default \
    && rm /var/www/html/* \
    && apt clean \
    && mkdir -p /app/.config/containers/ \
    && echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /app/.config/containers/policy.json \
    && chown -R app:app /app/ /var/lib/nginx/ /run /var/log/nginx/

WORKDIR /app
COPY --from=build-stage \
    /dist/* \
    /usr/local/bin/

RUN set -e \
    && ln -s /usr/local/bin/* /var/www/html/


USER app

CMD ["nginx", "-g", "daemon off;"]
