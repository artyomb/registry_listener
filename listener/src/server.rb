#!/bin/env ruby
require 'grape'
require_relative 'registry_events'
require_relative 'update_service'
require_relative 'check_services'

class StackManagerApi < Grape::API
  helpers RegistryEvents
  helpers UpdateService
  helpers CheckServices

  format :json
  # content_type :json, 'application/json'

  post '/on_registry_events', &-> { on_registry_events params[:events] }
  post '/update_services', &-> { update_services params[:image], params[:digest] }
  post '/check_services', &-> { check_services }

  get '/healthcheck', &-> {  } # LOGGER.debug :healthcheck
end

# always return json mime type
class Grape::Middleware::Base
  def mime_types = ->(_){ :json }
end
