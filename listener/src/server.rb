#!/bin/env ruby
require 'grape'
require_relative 'registry_event'

class StackManagerApi < Grape::API
  helpers RegistryEvent

  format :json
  content_type :json, 'application/json'
  content_type :json, 'text/plain'
  content_type :json, 'application/vnd.docker.distribution.events.v1+json'

  post '/registry_event', &-> { registry_event }

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck
end
