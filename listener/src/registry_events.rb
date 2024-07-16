require 'rest-client'
require 'async'
require 'async/semaphore'
require 'logger'


module RegistryEvents
  extend self

  otl_def def on_registry_events(events)
    events.each.map_async do |event|
      next unless event[:action] == 'push'

      target = event[:target]
      image = "#{target[:url][%r{(?:http|https)://([^/]+/)}, 1]}#{target[:repository]}:#{target[:tag]}".gsub(/:$/, '')

      next if target[:tag].to_s.empty?

      UPDATE_ENDPOINTS.map_async do |endpoint|
        RestClient.post endpoint, { image:, digest: target[:digest] }.to_json, content_type: :json, accept: :json
      end
    end
  end
end
