require 'rest-client'

module RegistryEvents
  extend self

  def split_image_string(image_string)
    host, *path = image_string.split('/')
    host =~ /[.:]/ ? [host, path.join('/')] : [nil, image_string]
  end

  otl_def def push_to_registry(to, image, auth)
    _, short_image = split_image_string image
    to_ = to.gsub %r{/$}, ''
    if auth
      login, password = auth.split(':')
      exec_ "docker login #{to_} -u #{login} -p #{password}"
    end
    exec_ "docker pull #{image}"
    exec_ "docker tag #{image} #{to_}/#{short_image}"
    exec_ "docker push #{to_}/#{short_image}"

    notify "Image re-pushed to: #{to_}/#{short_image}"
  end

  async otl_def def on_registry_events(events)
    events.each.map_async do |event|
      next unless event[:action] == 'push'
      LOGGER.info event

      target = event[:target]
      image = "#{target[:url][%r{(?:http|https)://([^/]+/)}, 1]}#{target[:repository]}:#{target[:tag]}".gsub(/:$/, '')

      next if target[:tag].to_s.empty?

      CONFIG[:OnPush]&.map_async do |on_push|
        next unless image =~ on_push[:image] # regexp
        notify "New image pushed: #{image}"

        on_push[:Push]&.map_async do |push|
          push_to_registry push[:to], image, push[:auth]

          push[:UpdateServices]&.map_async do |update|
            _, short_image = split_image_string image

            if update[:endpoint] == :local
              UpdateService.update_services short_image, event[:digest]
            else
              RestClient.post update[:endpoint], { image: short_image, digest: event[:digest] }.to_json, content_type: :json, accept: :json
            end
          end

        end
      end
    end
  end
end
