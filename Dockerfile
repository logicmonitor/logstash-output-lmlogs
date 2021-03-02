FROM jruby:latest
RUN mkdir /lmlogs
COPY . /lmlogs
WORKDIR /lmlogs
RUN bundle install
RUN bundle exec rake vendor
RUN bundle exec rspec spec
RUN gem build logstash-output-lmlogs.gemspec
