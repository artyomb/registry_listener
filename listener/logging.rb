ENV['CONSOLE_LEVEL'] ||= 'all'
TRACE_METHODS = true
LOG_DEPTH = (ENV['LOG_DEPTH'] || 10).to_i
ENV['CONSOLE_OUTPUT'] = 'XTerm'
ENV['CONSOLE_FATAL'] = 'Async::IO::Socket'

require 'console'
require 'fiber'

TracePoint.new(:call, :return, :b_call, :b_return) { |tp|
  cs = Thread.current[:call_stack] ||= {}
  csf = cs[Fiber.current.object_id] ||= []
  csf << [tp.defined_class, tp.method_id] if %i[call b_call].include?(tp.event)
  csf.pop if %i[return b_return].include?(tp.event)
}.enable if TRACE_METHODS

# LOGGER = Console.logger
LOGGER = Class.new {
  def method_missing(name, *args, &)
    return if name[/\d+/].to_i > LOG_DEPTH
    if TRACE_METHODS
      cs = Thread.current[:call_stack] ||= {}
      csf = cs[Fiber.current.object_id] ||= []
      caller = csf[-2]&.join('.')&.gsub('Class:', '')&.gsub(/[<>#]/, '') || ''
      msg = "\e[33m#{caller}:\e[0m \e[38;5;254m"
      Console.logger.send(name.to_s.gsub(/\d/, ''), msg, *args, &)
    else
      Console.logger.send(name.to_s.gsub(/\d/, ''), *args, &)
    end
  end
}.new
