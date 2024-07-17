#!/bin/env ruby
require 'grape'
require_relative 'registry_events'
require_relative 'update_service'

class StackManagerApi < Grape::API
  helpers RegistryEvents
  helpers UpdateService

  format :json
  # content_type :json, 'application/json'
  content_type :json, 'application/vnd.docker.distribution.events.v1+json'

  post '/on_registry_events', &-> { on_registry_events params[:events] }
  post '/update_services', &-> { update_services params[:image], params[:digest] }

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck
end
