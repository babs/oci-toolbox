ARG GOLANG_VERSION="1.24.2"

FROM golang:${GOLANG_VERSION}-bookworm AS build-stage

WORKDIR /app

RUN mkdir /dist

ENV CGO_ENABLED=0

RUN go install github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login@latest
RUN go install github.com/a8m/envsubst/cmd/envsubst@v1.4.3
RUN go install github.com/babs/ecr-repo-creator@latest

COPY --from=ghcr.io/jqlang/jq /jq /dist/
COPY --from=mikefarah/yq /usr/bin/yq /dist/
COPY --from=ghcr.io/babs/skopeo-static:1 /usr/local/bin/skopeo /dist/
COPY --from=ghcr.io/oras-project/oras:v1.2.0 /bin/oras /dist/
COPY --from=mplatform/manifest-tool /manifest-tool /dist/

RUN set -eu \
    && git clone https://github.com/opencontainers/umoci $GOPATH/src/github.com/opencontainers/umoci \
    && cd $GOPATH/src/github.com/opencontainers/umoci && make \
    && mv umoci /dist/

COPY get-helm.sh .
RUN set -ue \
    && cp /dist/* /usr/local/bin/ \
    && ./get-helm.sh \
    && mv helm /dist/

RUN set -ue \
    && cp /go/bin/envsubst \
        /go/bin/ecr-repo-creator \
        /go/bin/docker-credential-ecr-login \
        /dist \
    && chmod +rx /dist/*

RUN ls -alh /dist

FROM debian:bookworm-slim AS final-stage

RUN set -e \
    && apt update \
    && apt install -y curl nginx-light \
    && chown -R www-data:www-data /var/lib/nginx/ /run \
    && sed -i '/try_files $uri $uri\/ =404/a autoindex on;' /etc/nginx/sites-enabled/default \
    && rm /var/www/html/* \
    && apt clean \
    && useradd -md /app app

WORKDIR /app
COPY --from=build-stage \
    /dist/* \
    /usr/local/bin/

RUN set -e \
    && ln -s /usr/local/bin/* /var/www/html/


USER www-data

CMD ["nginx", "-g", "daemon off;"]
