# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/lmlogs"
require "logstash/event"

describe LogStash::Outputs::LMLogs do

    let(:sample_lm_logs_event){{"message" => "hello this is log 1", "_lm.resourceId" => {"test.property" => "host1"}, "timestamp" => "2021-03-22T04:28:55.907121106Z"}}

    def create_output_plugin_with_conf(conf)
        return LogStash::Outputs::LMLogs.new(conf)
    end 

    it "with no auth specified" do
        puts "auth test"
        plugin = create_output_plugin_with_conf({
            "portal_name" => "localhost"
        })
        expect { plugin.configure_auth() }.to raise_error(LogStash::ConfigurationError)
    end

    it "access_key id is specified with no bearer" do
        puts "auth test"
        plugin = create_output_plugin_with_conf({
            "portal_name" => "localhost",
            "access_id" => "abcd",
            "access_key" => "abcd"
        })
        plugin.configure_auth()
        auth_string  = plugin.generate_auth_string([sample_lm_logs_event])

        expect(auth_string).to start_with("LMv1 abcd:")
    end

    it "when access id /key not specified but bearer specified" do
        plugin = create_output_plugin_with_conf({
            "portal_name" => "localhost",
            "access_id" => "abcd",
            "bearer_token" => "abcd"
        })
        plugin.configure_auth()
        auth_string  = plugin.generate_auth_string([sample_lm_logs_event])

        expect(auth_string).to eq("Bearer abcd")
    end

    it "when access id /key bearer all specified, use lmv1" do
        puts "auth test"
        plugin = create_output_plugin_with_conf({
            "portal_name" => "localhost",
            "access_id" => "abcd",
            "access_key" => "abcd",
            "bearer_token" => "abcd"
        })
        plugin.configure_auth()
        auth_string  = plugin.generate_auth_string([sample_lm_logs_event])

        expect(auth_string).to start_with("LMv1 abcd:")
    end
end
