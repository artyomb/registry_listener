require 'async/semaphore'

UPDATE_PERIOD = (ENV['UPDATE_PERIOD'] || 60) # RegExp 127.0.0.1:5000/my-image:latest
IMAGE_FILTER = Regexp.new(ENV['IMAGE_FILTER'] || "127\.0\.0\.1:5000") # RegExp 127.0.0.1:5000/my-image:latest
HOSTS = ENV['DOCKER_HOSTS'].to_s.split ',' # unix:///var/run/docker.sock

UPDATE_ENDPOINTS = ENV['UPDATE_ENDPOINTS'].to_s.split ',' # https://127.0.0.1:5000/update_services

raise 'DOCKER_HOSTS not set' if HOSTS.empty?
LOGGER.warn "TELEGRAM TOKEN, CHAT_ID not set" unless ENV['TELEGRAM_BOT_TOKEN'] && ENV['TELEGRAM_CHAT_ID']

HOSTS = HOSTS.map do |host|
  ctx = "ctx-#{host.gsub(%r{^ssh://|^unix://}, '').gsub(/[@:.\/]/, '-')}"
  exec_ "docker context create #{ctx} --docker \"host=#{host}\"" \
    unless exec_('docker context ls --format {{.Name}}').include? ctx
  ctx
  [ctx, Async::Semaphore.new(1), host]
end