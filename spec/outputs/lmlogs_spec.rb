# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/lmlogs"
require "logstash/event"

describe LogStash::Outputs::LMLogs do
  let(:sample_event) { LogStash::Event.new("message" => "hello this is log") }
  let(:client) { @lmlogs.client }

  before do
    @lmlogs = LogStash::Outputs::LMLogs.new(
      "portal_name" => "localhost",
      "access_id" => "access_id",
      "access_key" => "access_key",
      "batch_size" => 3,
      "lm_property" => "test.property"
      )
    @lmlogs.register
    allow(@lmlogs).to receive(:client).and_return(client)
    allow(client).to receive(:post).and_call_original
  end

  before do
    allow(@lmlogs).to receive(:client).and_return(client)
  end

  it "Forwards an event" do
      expect(client).to receive(:post).once.and_call_original
      @lmlogs.multi_receive([sample_event])
  end

  it "Batches multiple events and extracts metadata" do
    event1 = LogStash::Event.new("message" => "hello this is log 1", "host" => "host1")
    event2 = LogStash::Event.new("message" => "hello this is log 2", "host" => "host2")
    event3 = LogStash::Event.new("message" => "hello this is log 3", "host" => "host3")
    expect(client).to receive(:post).once.with("https://localhost.logicmonitor.com/rest/log/ingest",hash_including(:body => LogStash::Json.dump(
        [{"message" => "hello this is log 1", "_lm.resourceId" => {"test.property" => "host1"}, "timestamp" => event1.timestamp.to_s},
        {"message" => "hello this is log 2", "_lm.resourceId" => {"test.property" => "host2"}, "timestamp" => event2.timestamp.to_s},
        {"message" => "hello this is log 3", "_lm.resourceId" => {"test.property" => "host3"}, "timestamp" => event3.timestamp.to_s}
        ]
        ))).and_call_original
    @lmlogs.multi_receive([event1, event2, event3])
  end

  it "Batches data of size batch_size" do
    expect(client).to receive(:post).exactly(2).times.and_call_original
    @lmlogs.multi_receive([sample_event, sample_event, sample_event, sample_event, sample_event])
  end


end
