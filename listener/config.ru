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

module AsyncWarmup
  def initialize(...)
    super(...)
    self.async do
        loop do
          sleep UPDATE_PERIOD.to_i
          UpdateService.update_services
        end
    end if @parent.is_a? Async::Reactor # root task
  end
end

Async::Task.prepend AsyncWarmup

if defined? OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware
  use OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware
end

# warmup do
#   @options[:debug] = true
# end

run StackManagerApi

