#!/usr/bin/env ruby
require_relative 'logging'
require_relative 'otlp'
require_relative 'helpers'
require_relative 'config.rb'
require_relative 'src/server'

# disable logging for Async::IO::Socket, Falcon::Server
Console.logger.enable Class, 3
# Console.logger.enable Falcon::Server, 3

otel_initialize

# Async do
#   # if UPDATE_PERIOD
#   #   Async do
#   #     loop do
#   #       sleep UPDATE_PERIOD.to_i
#   #       UpdateService.update_services
#   #     end
#   #   end
#   # end
# end
run StackManagerApi


