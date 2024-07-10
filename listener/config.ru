#!/usr/bin/env ruby
require_relative 'logging'
require_relative 'otlp'
require_relative 'src/server'

# disable logging for Async::IO::Socket, Falcon::Server
Console.logger.enable Class, 3
# Console.logger.enable Falcon::Server, 3

otel_initialize
run StackManagerApi