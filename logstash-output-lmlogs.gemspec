Gem::Specification.new do |s|
  s.name = 'logstash-output-lmlogs'
  s.version         = '1.1.0'
  s.licenses = ['Apache-2.0']
  s.summary = "Logstash output plugin for LM Logs"
  s.description     = "This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program"
  s.authors = ["LogicMonitor"]
  s.email = "support@logicmonitor.com"
  s.homepage = "https://www.logicmonitor.com"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','Gemfile']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "output" , "rubygems_mfa_required" => "false"}

  # Gem dependencies
  #

  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency "logstash-codec-plain"
  s.add_runtime_dependency 'manticore', '>= 0.5.2', '< 1.0.0'

  s.add_development_dependency 'logstash-devutils'
end
