require_relative 'otlp'
require 'async'
require 'open3'

otl_def def exec_(command)
  stdout, stderr, status = Open3.capture3(command)
  output = stdout.strip
  yield output, status.exitstatus if block_given?

  unless status.exitstatus.zero?
    LOGGER.error "Command failed: #{command}\nOutput: #{output}\nError: #{stderr.strip}"
    raise "Command failed: #{command}\nOutput: #{output}\nError: #{stderr.strip}"
  end
  LOGGER.info "Command succeeded: #{command}\nOutput: #{output}"
  output
end

def async(name)
  original_method = self.respond_to?(:instance_method) ? instance_method(name) : method(name)
  self.respond_to?(:remove_method) ? remove_method(name) : Object.send(:remove_method, name)
  original_method = original_method.respond_to?(:unbind) ? original_method.unbind : original_method

  define_method(name) do |*args, **kwargs, &block|
    Async do
      original_method.bind(self).call(*args, **kwargs, &block)
    end
  end
end

module Enumerable
  def map_async
    self.map do |item|
      Async do
        item.respond_to?(:to_ary) ? yield(*item.to_ary) : yield(item)
      end
    end.map(&:wait)
  end
end

$notify_queue = []
$notify_task = nil

def notify(message)
  $notify_queue << message unless message.nil?
  $notify_task&.stop
  $notify_task = Async do
    sleep 2
    b_message = ''
    until $notify_queue.empty?
      break if $notify_queue.first.size + "\n".size + b_message.size >= 4096
      b_message += "\n" unless b_message.empty?
      b_message += $notify_queue.shift
    end
    notify_bulk b_message unless b_message.empty?
    Async { notify nil } unless $notify_queue.empty?
  end
end

otl_def def notify_bulk(message)
  return unless ENV['TELEGRAM_BOT_TOKEN'] && ENV['TELEGRAM_CHAT_ID']
  RestClient.post \
    "https://api.telegram.org/bot#{ENV['TELEGRAM_BOT_TOKEN']}/sendMessage",
    { chat_id: ENV['TELEGRAM_CHAT_ID'], text: message, parse_mode: 'HTML' }.to_json,
    content_type: :json, accept: :json
rescue => e
  LOGGER.error "Notification failed: #{e.message}, (response: #{e.response rescue 'n/a'})"
end
