#!/bin/env ruby
require 'grape'
require_relative 'registry_event'
require_relative 'update_service'

otl_def def exec_(command)
  stdout, stderr, status = Open3.capture3(command)
  output = stdout.strip
  unless status.exitstatus.zero?
    LOGGER.error "Command failed: #{command}\nOutput: #{output}\nError: #{stderr.strip}"
    raise "Command failed: #{command}\nOutput: #{output}\nError: #{stderr.strip}"
  end
  LOGGER.info "Command succeeded: #{command}\nOutput: #{output}"
  output
end

UPDATE_PERIOD = (ENV['UPDATE_PERIOD'] || nil) # RegExp 127.0.0.1:5000/my-image:latest
IMAGE_FILTER = Regexp.new(ENV['IMAGE_FILTER'] || "127\.0\.0\.1:5000") # RegExp 127.0.0.1:5000/my-image:latest
HOSTS = ENV['DOCKER_HOSTS'].to_s.split ',' # unix:///var/run/docker.sock
raise 'DOCKER_HOSTS not set' if HOSTS.empty?
LOGGER.warn "TELEGRAM TOKEN, CHAT_ID not set" unless ENV['TELEGRAM_BOT_TOKEN'] && ENV['TELEGRAM_CHAT_ID']

HOSTS = HOSTS.map do |host|
  ctx = "ctx-#{host.gsub(%r{^ssh://|^unix://}, '').gsub(/[@:.\/]/, '-')}"
  exec_ "docker context create #{ctx} --docker \"host=#{host}\"" \
    unless exec_('docker context ls --format {{.Name}}').include? ctx
  ctx
  [ctx, Async::Semaphore.new(1), host]
end

class StackManagerApi < Grape::API
  helpers RegistryEvent
  helpers UpdateService

  format :json
  content_type :json, 'application/json'
  content_type :json, 'text/plain'
  content_type :json, 'application/vnd.docker.distribution.events.v1+json'

  post '/registry_event', &-> { registry_event }
  post '/update_services', &-> { update_services }

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck

  # def initialize(...)
  #   Async do
  #     loop do
  #       sleep UPDATE_PERIOD.to_i
  #       update_services
  #     end
  #   end if UPDATE_PERIOD
  #   super
  # end
end
