FROM ruby:3.2-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential default-libmysqlclient-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 4.0.10 --no-document && bundle install

COPY . .

CMD ["sh", "-c", "bin/rails db:prepare && bundle exec rspec"]
