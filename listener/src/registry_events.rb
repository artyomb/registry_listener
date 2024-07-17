require 'rest-client'

module RegistryEvents
  extend self

  def split_image_string(image_string)
    host, path = image_string.split('/', 2)
    path ? [host, path] : [nil, host]
  end

  otl_def def push_to_registry(to, image)
    _, short_image = split_image_string image
    to_ = to.gsub %r{/$}, ''

    exec_ "docker pull #{image}"
    exec_ "docker tag #{image} #{to_}/#{short_image}"
    exec_ "docker push #{to_}/#{short_image}"
  end

  otl_def def on_registry_events(events)
    events.each.map_async do |event|
      next unless event[:action] == 'push'
      LOGGER.info event

      target = event[:target]
      image = "#{target[:url][%r{(?:http|https)://([^/]+/)}, 1]}#{target[:repository]}:#{target[:tag]}".gsub(/:$/, '')

      next if target[:tag].to_s.empty?

      CONFIG[:OnPush].map_async do |on_push|
        next unless image =~ on_push[:image] # regexp

        on_push[:Push].map_async do |push|
          push_to_registry push[:to], image
        end

        on_push[:UpdateServices].map_async do |update|
          if update[:endpoint] == :local
            UpdateService.update_services image, nil # digest
          else
            RestClient.post update[:endpoint], { image:, target: }.to_json, content_type: :json, accept: :json
          end
        end
      end
    end
  end
end
