#FROM jruby:9.3.9.0-jdk11
FROM logstash:8.5.1 AS builder

FROM jruby:9.3.9.0-jdk11
COPY --from=builder /usr/share/logstash /logstash
RUN mkdir /logicmonitor
COPY . /logicmonitor
WORKDIR /logicmonitor
#skipping tests due to logstash bug causing failure
# todo add logstash bug workaround for failing tests
ENV LOGSTASH_SOURCE='1'
ENV LOGSTASH_PATH='/logstash'
RUN bundle install
RUN bundle exec rake vendor
RUN bundle exec rspec spec
RUN gem build logstash-output-lmlogs.gemspec
RUN mv logstash-output-lmlogs-*.gem release.gem
