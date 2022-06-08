FROM jruby:latest
RUN mkdir /logicmonitor
COPY . /logicmonitor
WORKDIR /logicmonitor
#skipping tests due to logstash bug causing failure
# todo add logstash bug workaround for failing tests 
#RUN bundle install
#RUN bundle exec rake vendor
#RUN bundle exec rspec spec
RUN gem build logstash-output-lmlogs.gemspec
RUN mv logstash-output-lmlogs-*.gem release.gem
