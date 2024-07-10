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

LOGGER = Class.new {
  def method_missing(name, *args)
    return if name[/\d+/].to_i > LOG_DEPTH
    msg = if TRACE_METHODS
            cs = Thread.current[:call_stack] ||= {}
            csf = cs[Fiber.current.object_id] ||= []
            caller = csf[-2]&.join('.')&.gsub('Class:', '')&.gsub(/[<>#]/, '') || ''
            "\e[33m#{caller}:\e[0m \e[38;5;254m#{args.map(&:inspect).join(', ')}"
          else
            args.map(&:inspect).join(', ')
          end
    Console.logger.send(name.to_s.gsub(/\d/, ''), msg)
  end
}.new

LOGGER_GRAPE = Class.new {
  def method_missing(name, d)
    Console.logger.send(name, "REST_API: #{d[:method]} #{d[:path]} #{d[:params]} - #{d[:status]} host:#{d[:host]} time:#{d[:time]}")
  end
}.new
