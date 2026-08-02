# Demo image for the kyufy_core assessment API — NOT a production image (it runs
# RAILS_ENV=development, with no auth, no TLS, and no secret management).
#
# It boots the in-repo dummy host app (test/dummy), which mounts the engine at /kyufy_core.
# That gives any language a plain HTTP endpoint for 該当 / 非該当 / 要確認 assessments without
# installing Ruby, PostgreSQL, or pgvector locally.

ARG RUBY_VERSION=4.0.6
FROM ruby:${RUBY_VERSION}-slim

# libpq-dev + build-essential: the pg gem's native extension. postgresql-client: pg_isready,
# used by the entrypoint to wait out the database.
RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y build-essential libpq-dev postgresql-client \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    RAILS_LOG_TO_STDOUT=1 \
    # pg_dump in this image won't match every PostgreSQL server major version, and the container
    # has no reason to refresh structure.sql (maintainers migrate in RAILS_ENV=test). See
    # test/dummy/config/environments/development.rb.
    KYUFY_SKIP_SCHEMA_DUMP=1

# Keep in sync with Gemfile.lock's "BUNDLED WITH".
ARG BUNDLER_VERSION=4.0.16
RUN gem install bundler -v "${BUNDLER_VERSION}"

# Gems first, so editing engine source doesn't re-resolve the bundle. Bundler evaluates the
# gemspec, which reads lib/kyufy_core/version.rb — that file has to be present at this point.
COPY Gemfile Gemfile.lock kyufy_core.gemspec ./
COPY lib/kyufy_core/version.rb lib/kyufy_core/version.rb
RUN bundle install

COPY . .

RUN chmod +x docker/entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["docker/entrypoint.sh"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
