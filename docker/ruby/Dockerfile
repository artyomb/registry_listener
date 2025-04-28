FROM ruby:3.3.1-slim-bookworm AS base

RUN apt update && apt --fix-missing install -y build-essential pkg-config bash curl libpq-dev openssh-client \
     libpq-dev libsqlite3-dev libssl-dev libgeos-dev docker.io jq\
     && rm -rf /var/lib/apt/lists/*

RUN echo 'gem: --no-document' >> ~/.gemrc

WORKDIR /app

COPY .ruby-version Gemfile* /app/
RUN bundle install --jobs $(nproc) --retry=3 && \
    bundle clean --force && rm -rf /usr/local/bundle/cache/*

FROM ruby:3.3.1-slim-bookworm AS deploy
RUN apt update && apt install --fix-missing -y bash curl libpq-dev openssh-client \
      libpq-dev sqlite3 libssl-dev libgeos-dev docker.io jq\
     && rm -rf /var/lib/apt/lists/*

COPY --from=base /usr/local/bundle /usr/local/bundle
COPY . /app

ENV SERVER_ENV=production \
    RACK_ENV=production \
    PORT=7000

WORKDIR /app

# --start_period=5s (Unknown flag: start_period)
HEALTHCHECK --interval=15s --timeout=2s --retries=3 CMD curl --fail http://127.0.0.1:$PORT/healthcheck || exit 1
CMD ls && bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon