FROM ruby:3.3.1-alpine as base

RUN apk add --update build-base \
    bash openssh-client git \
    postgresql-dev libpq libpq-dev \
    mysql sqlite-dev openssl-dev mariadb-dev \
    && rm -rf /var/cache/apk/*

RUN echo 'gem: --no-document' >> ~/.gemrc
WORKDIR /app

COPY .ruby-version Gemfile* /app/
RUN bundle install --jobs $(nproc)

FROM ruby:3.3.1-alpine AS deploy

RUN apk add docker-cli openssh-client bash curl jq && rm -rf /var/cache/apk/*

COPY --from=base /usr/local/bundle /usr/local/bundle

COPY . /app

ENV SERVER_ENV=production \
    RACK_ENV=production \
    PORT=7000

WORKDIR /app

# --start_period=5s (Unknown flag: start_period)
HEALTHCHECK --interval=15s --timeout=2s --retries=3 CMD curl --fail http://127.0.0.1:$PORT/healthcheck || exit 1
CMD ls && bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon
