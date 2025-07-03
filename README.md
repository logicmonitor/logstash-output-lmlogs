[![Gem Version](https://badge.fury.io/rb/logstash-output-lmlogs.svg)](https://badge.fury.io/rb/logstash-output-lmlogs)

This plugin sends Logstash events to the [Logicmonitor Logs](https://www.logicmonitor.com)

# Getting started

## Installing through rubygems

Run the following on your Logstash instance

`logstash-plugin install logstash-output-lmlogs`

## Minimal configuration
```
output {
    lmlogs {
        portal_name => "your company name"
        portal_domain => "your LM company domain."
        access_id => "your lm access id"
        access_key => "your access key"
    }
}
```
You would need either `access_id` and `access_id` both or `bearer_token` for authentication with Logicmonitor. 
The portal_domain is the domain of your LM portal. If not set the default is set to `logicmonitor.com`. Eg if your LM portal URL is `https://test.lmgov.us`, portal_name should be set to `test` and portal_domain to `lmgov.us`
The allowed values for portal_domain are ["logicmonitor.com", "lmgov.us", "qa-lmgov.us"]



## Important options

| Option                | Description                                                                                                                                                                                                                                                                                                                                                                                     | Default           |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------|
| batch_size            | Event batch size to send to LM Logs.                                                                                                                                                                                                                                                                                                                                                            | 100               |
| message_key           | Key that will be used by the plugin as the system key                                                                                                                                                                                                                                                                                                                                           | "message"         |
| lm_property           | Key that will be used by LM to match resource based on property                                                                                                                                                                                                                                                                                                                                 | "system.hostname" |
| keep_timestamp        | If false, LM Logs will use the ingestion timestamp as the event timestamp                                                                                                                                                                                                                                                                                                                       | true              |
| timestamp_is_key      | If true, LM Logs will use a specified key as the event timestamp                                                                                                                                                                                                                                                                                                                                | false             |
| timestamp_key         | If timestamp_is_key is set, LM Logs will use this key in the event as the timestamp                                                                                                                                                                                                                                                                                                             | "logtimestamp"    |
| include_metadata      | If true, all metadata fields will be sent to LM Logs                                                                                                                                                                                                                                                                                                                                            | false             |
| include_metadata_keys | Array of json keys for which plugin looks for these keys and adds as event meatadata. A dot "." can be used to add nested subjson. If config `include_metadata` is set to true, all metadata will be sent regardless of this config.                                                                                                                                                            | []                |
| resource_type         | If a Resource Type is explicitly specified, that value will be statically applied to all ingested logs. If set to `predef.externalResourceType`, the Resource Type will be assigned dynamically based on the `predef.externalResourceType` property set for the specific resource the logs are mapped to in LM. If left blank, the Resource Type field will remain unset in the ingested logs.  | ""                |
See the [source code](lib/logstash/outputs/lmlogs.rb) for the full list of options

The syntax for `message_key` and `source_key` values are available in the [Logstash Event API Documentation](https://www.elastic.co/guide/en/logstash/current/event-api.html)

## Known issues
 - Installation of the plugin fails on Logstash 6.2.1.


 ## Contributing

 Bug reports and pull requests are welcome. This project is intended to
 be a safe, welcoming space for collaboration.

 ## Development

We use docker to build the plugin. You can build it by running  `docker-compose run jruby gem build logstash-output-lmlogs.gemspec `
