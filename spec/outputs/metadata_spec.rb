# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/lmlogs"
require "logstash/event"
require "hashdiff"


describe LogStash::Outputs::LMLogs do


    let(:logstash_event) {LogStash::Event.new("message" => "hello this is log 1",
    "host" => "host1",
    "nested1" => {"nested2" => {"nested3" => "value"},
                  "nested2a" => {"nested3a" => {"nested4" => "valueA"}},
                  "nested2b" => {"nested3b" => "value"}
                      },
    "nested1_" => "value",
    "nested" => {"nested2" => {"nested3" => "value",
                                "nested3b" => "value"},
                  "nested_ignored" => "somevalue"
                }
    )}
    let(:sample_lm_logs_event){{"message" => "hello this is log 1", "_lm.resourceId" => {"test.property" => "host1"}, "timestamp" => "2021-03-22T04:28:55.907121106Z"}}
    let(:include_metadata_keys) {["host", "nested1.nested2.nested3", "nested1.nested2a", "nested.nested2" ]}

    def create_output_plugin_with_conf(conf)
        return LogStash::Outputs::LMLogs.new(conf)
    end

    def check_same_hash(h1,h2)

    end

    it "default behaviour" do
      puts "default behaviour"
      plugin = create_output_plugin_with_conf({
          "portal_name" => "localhost",
          "access_id" => "abcd",
          "access_key" => "abcd",
          "lm_property" => "system.hostname",
          "property_key" => "host"
      })
      constructed_event = plugin.processEvent(logstash_event)
      expected_event = {
        "message" => "hello this is log 1",
        "timestamp" => logstash_event.timestamp,
        "_lm.resourceId" => {"system.hostname" => "host1"}
      }
      puts " actual : #{constructed_event} \n expected : #{expected_event}"

      expect(Hashdiff.diff(constructed_event,expected_event)).to eq([])
    end

    it "with include_metadata set to true" do
      puts "with include_metadata set to true"
      plugin = create_output_plugin_with_conf({
        "portal_name" => "localhost",
        "access_id" => "abcd",
        "access_key" => "abcd",
        "lm_property" => "system.hostname",
        "property_key" => "host",
        "include_metadata" => true
      })
      constructed_event = plugin.processEvent(logstash_event)
      expected_event = {
        "message" => "hello this is log 1",
        "timestamp" => logstash_event.timestamp,
        "@version" => "1",
        "_lm.resourceId" => {"system.hostname" => "host1"},
        "host" => "host1",
        "nested1" => {"nested2" => {"nested3" => "value"},
                      "nested2a" => {"nested3a" => {"nested4" => "valueA"}},
                      "nested2b" => {"nested3b" => "value"}
                      },
        "nested1_" => "value",
        "nested" => {"nested2" => {"nested3" => "value",
                                "nested3b" => "value"},
                    "nested_ignored" => "somevalue"
                  },
        "_resource.type"=>"Logstash"
      }
      puts " actual : #{constructed_event} \n expected : #{expected_event}"
      puts " hash diff : #{Hashdiff.diff(constructed_event,expected_event)}"
      expect(Hashdiff.diff(constructed_event,expected_event)).to eq([])
    end

    it "Netsted key that doesn not exist should not break" do
      plugin = create_output_plugin_with_conf({
        "portal_name" => "localhost",
        "access_id" => "abcd",
        "access_key" => "abcd",
        "lm_property" => "system.hostname",
        "property_key" => "host",
        "include_metadata_keys" => %w[nested1.nested2.nestedkey_that_doesnt_exist]
      })
      constructed_event = plugin.processEvent(logstash_event)
      expected_event = {
        "message" => "hello this is log 1",
        "timestamp" => logstash_event.timestamp,
        "_lm.resourceId" => {"system.hostname" => "host1"}
      }
      puts " actual : #{constructed_event} \n expected : #{expected_event}"
      puts " hash diff : #{Hashdiff.diff(constructed_event,expected_event)}"
      expect(Hashdiff.diff(constructed_event,expected_event)).to eq([])
    end


end
