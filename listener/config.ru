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
    if @parent.is_a? Async::Reactor # root task
      self.async do
        loop do
          sleep 10
          notify(nil) rescue 'ok' # send messages in the queue
        end
      end

      CONFIG[:OnTime]&.each do |on_time|
        self.async do
          loop do
            sleep (on_time[:minutes] || 10) * 60
            otl_span :on_time do
              on_time[:block].call
            end
          end
        end
      end

      self.async do
        loop do
          sleep UPDATE_PERIOD.to_i
          otl_span :periodic_update do
            UpdateService.update_services
          end rescue 'ok'

          otl_span :periodic_check do
            CheckServices.check_services
          end rescue 'ok'
        end
      end
    end
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

