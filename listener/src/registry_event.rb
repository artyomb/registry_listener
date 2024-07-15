require 'rest-client'
require 'async'
require 'async/semaphore'
require 'logger'
require 'open3'

module RegistryEvent
  extend self

  otl_def def registry_event(events)
    Async do
      events.each do |event|
        next unless event[:action] == 'push'
        target = event[:target]
        image = "#{target[:url][%r{(?:http|https)://([^/]+/)}, 1]}#{target[:repository]}:#{target[:tag]}".gsub(/:$/, '')
        next if target[:tag].to_s.empty?
        CONTEXTS.each { |ctx| update_services_ ctx, image, target[:digest] }
      end
    end
  end

  private

  otl_def def update_services_(ctx, image, new_digest)
    services = exec_("docker --context #{ctx} service ls -f label=com.docker.stack.image=#{image.gsub(/:latest$/, '')} --format {{.Name}}").split
    Async do
      services.each do |name|
        SEMAPHORES[host].acquire do
          current_digest = exec_("docker --context #{ctx} service inspect #{name} --format '{{.Meta.Digest}}'").strip
          if current_digest != new_digest
            result = exec_("docker --context #{ctx} service update --force #{name} --image #{image} 2>&1")
            message = result.include?('update successful') ? "Updated #{name} on #{host}" : "Failed to update #{name} on #{host}"
            LOGGER.info message
            notify message
          end
        end
      end
    end
  rescue => e
    LOGGER.error "Error on #{host}: #{e.message}"
  end

  otl_def def notify(message)
    return unless ENV['TELEGRAM_BOT_TOKEN'] && ENV['TELEGRAM_CHAT_ID']
    RestClient.post \
      "https://api.telegram.org/bot#{ENV['TELEGRAM_BOT_TOKEN']}/sendMessage",
      { chat_id: ENV['TELEGRAM_CHAT_ID'], text: message, parse_mode: 'HTML' }.to_json,
      content_type: :json, accept: :json
  rescue => e
    LOGGER.error "Notification failed: #{e.message}"
  end
end