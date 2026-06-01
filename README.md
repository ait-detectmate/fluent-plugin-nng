# fluent-plugin-nng

[Fluentd](https://fluentd.org/) input and output plugin for [Nano Msg](https://nanomsg.org/).

## Installation

You can install this gem using the following command:

```
$ fluent-gem install fluent-plugin-nng
```

## Configuration

*nng_in configuration parameters*:

| Parameter      | Description      | Default |
| -------------- | -------------    | ------- |
| uri | bind socket | `tcp://127.0.0.1:5555`  |
| recv_timeout | Timeout for recv() | `1.0` |
| tag | fluentd tag | `nng.input` |
| cert | Server certificate (PEM string, OpenSSL::X509::Certificate, or Pathname) | `nil` |
| key  | Private key (PEM string, OpenSSL::PKey, or Pathname) | `nil` |
| ca | | CA certificate for client verification (mutual TLS) | `nil` |
| verify | Require client certificates | `false` |
| server_name | Expected server CN/SAN | calculated |

*nng_out configuration parameters*:

| Parameter      | Description      | Default |
| -------------- | -------------    | ------- |
| uri | connect uri | `tcp://127.0.0.1:5555`  |
| max_retry | Maximum reconnect | `100` |
| retry_time | Retry connecting after timeout. In seconds | `5` |
| cert | Server certificate (PEM string, OpenSSL::X509::Certificate, or Pathname) | `nil` |
| key  | Private key (PEM string, OpenSSL::PKey, or Pathname) | `nil` |
| ca | | CA certificate for client verification (mutual TLS) | `nil` |
| verify | Require client certificates | `false` |
| server_name | Expected server CN/SAN | calculated |
| format | Dataformat | `json` |


### Example for input plugin

This example creates a listening nanomsg socket, reads data from it and
parses the data using the fluentd-plugin [fluent-plugin-parser-protobuf](https://github.com/fluent-plugins-nursery/fluent-plugin-parser-protobuf):

```
<source>
  @type nng_in
  @id input_nng
  <parse>
    @type protobuf
    class_file /opt/schemas_pb.rb
    class_name LogSchema
    protobuf_version protobuf3
  </parse>
  uri tcp://127.0.0.1:5557
</source>

<match nng.**>
  @type stdout
</match>
```

### Example for output and formatter plugin

This example reads logs from a file(`/var/log/some.log`) and sends
the data to a nano msg socket. It automatically formats the data
using the detectmate `LogSchema` using [fluent-plugin-detectmate](https://github.com/ait-detectmate/fluent-plugin-detectmate). 

```
<source>
  @type tail
  @id input_tail
  <parse>
    @type none
  </parse>
  path /var/log/some.log
  path_key logSource

  tag nng.*
</source>

<match nng.**>
  @type nng_out
  uri tcp://127.0.0.1:5557
  <inject>
    hostname_key hostname
    # overwrite hostname:
    # hostname somehost
  </inject>
  <buffer>
    flush_mode immediate
  </buffer>
  <format>
    @type detectmate
  </format>
</match>
```

## Limitations

Currently only PAIR communication for nng is supported.

## Copyright

* Copyright(c) 2026- whotwagner
* License
  * EUROPEAN UNION PUBLIC LICENCE, Version 1.2
