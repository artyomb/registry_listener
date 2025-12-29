FROM ruby:3.3.1-slim-bookworm AS base

RUN apt update && apt --fix-missing install -y build-essential pkg-config bash curl openssh-client \
     libssl-dev docker.io jq\
     && rm -rf /var/lib/apt/lists/*

RUN echo 'gem: --no-document' >> ~/.gemrc

WORKDIR /app

COPY .ruby-version Gemfile* /app/
RUN bundle install --jobs $(nproc) --retry=3 && \
    bundle clean --force && rm -rf /usr/local/bundle/cache/*

FROM ruby:3.3.1-slim-bookworm AS deploy
RUN apt update && apt install --fix-missing -y bash curl libpq-dev openssh-client libyaml-0-2 procps\
      libssl-dev jq libjson-c5 libwebsockets-dev \
     && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    apt update; apt install -y --no-install-recommends ca-certificates curl; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    . /etc/os-release; \
    printf "Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: %s\nComponents: stable\nSigned-By: /etc/apt/keyrings/docker.asc\n" "$VERSION_CODENAME" \
      > /etc/apt/sources.list.d/docker.sources; \
    apt update; apt install -y --no-install-recommends docker-ce-cli; \
    rm -rf /var/lib/apt/lists/*

RUN docker -v

COPY --from=base /usr/local/bundle /usr/local/bundle
COPY . /app

ENV SERVER_ENV=production \
    RACK_ENV=production \
    PORT=7000

WORKDIR /app

# --start_period=5s (Unknown flag: start_period)
HEALTHCHECK --interval=15s --timeout=2s --retries=3 CMD curl --fail http://127.0.0.1:$PORT/healthcheck || exit 1
CMD ls && bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon