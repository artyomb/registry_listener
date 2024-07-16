#!/bin/env ruby
require 'grape'
require_relative 'registry_event'
require_relative 'update_service'

class StackManagerApi < Grape::API
  helpers RegistryEvent
  helpers UpdateService

  format :json
  # content_type :json, 'application/json'
  content_type :json, 'application/vnd.docker.distribution.events.v1+json'

  post '/registry_event', &-> { registry_event }
  post '/update_services', &-> { update_services }

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck
end
