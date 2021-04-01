FROM jruby:latest
RUN mkdir /logicmonitor
COPY . /logicmonitor
WORKDIR /logicmonitor
RUN bundle install
RUN bundle exec rake vendor
RUN bundle exec rspec spec
RUN gem build logstash-output-lmlogs.gemspec
RUN mv logstash-output-lmlogs-*.gem release.gem
