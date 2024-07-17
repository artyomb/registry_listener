#!/bin/env ruby
require 'grape'
require_relative 'registry_events'
require_relative 'update_service'

class StackManagerApi < Grape::API
  helpers RegistryEvents
  helpers UpdateService

  format :json
  content_type :json, ['application/json', 'application/vnd.docker.distribution.events.v1+json']

  post '/on_registry_events', &-> { on_registry_events params[:events] }
  post '/update_services', &-> { update_services params[:image], params[:digest] }

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck
end

# Monkeypatch rack-cache to allow for multiple mime types (json)
# Example: content_type :json, ['application/json', 'application/vnd.docker.distribution.events.v1+json']
class Grape::Middleware::Base
  def mime_types
    @mime_types ||= content_types.each_pair.with_object({}) do |(k, v), types_without_params|
      [v].flatten.each do |vv|
        types_without_params[vv.split(';').first] = k
      end
    end
  end
end
