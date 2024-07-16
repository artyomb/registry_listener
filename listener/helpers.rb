require_relative 'otlp'
require 'async'
require 'open3'

otl_def def exec_(command)
  stdout, stderr, status = Open3.capture3(command)
  output = stdout.strip
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
    results = []
    self.each_with_index.map do |item, index|
      Async { results[index] = yield(*item.to_ary) }
    end.map(&:wait)
    results
  end
end
