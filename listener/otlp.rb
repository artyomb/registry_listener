
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'
require 'opentelemetry-api'

STACK_NAME = ENV['STACK_NAME'] || 'event_listener'
SERVICE_NAME = ENV['STACK_SERVICE_NAME'] || 'event_listener'
ENV['OTEL_RESOURCE_ATTRIBUTES'] ||= "deployment.environment=#{STACK_NAME}"

# Initialize the OpenTelemetry SDK
OpenTelemetry.logger = LOGGER
def otel_initialize
  OpenTelemetry::SDK.configure do |c|
    c.service_name = SERVICE_NAME
    c.use_all # enables all instrumentation!
    # c.tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
  end

  at_exit do
    OpenTelemetry.tracer_provider.force_flush
    OpenTelemetry.tracer_provider.shutdown
  end

  $tracer_ = OpenTelemetry.tracer_provider.tracer(SERVICE_NAME)
end

def otl_span(name, attributes = {})
  # span_ = OpenTelemetry::Trace.current_span
  # return yield(nil) unless OTEL_ENABLED

  return yield(nil) unless $tracer_
  $tracer_&.in_span(name, attributes: flatten_hash(attributes.transform_keys(&:to_s).transform_values{_1 || 'n/a'}) ) do |span|
    yield span
  end
end

def otl_def(name)
  original_method = instance_method(name)
  remove_method(name)

  define_method(name) do |*args, **kwargs, &block|
    klass = Module === self ? self.name : self.class_name
    otl_span("method: #{klass}.#{name}", {args: args.to_s, kwargs: kwargs.to_s}) do
      original_method.bind(self).call(*args, **kwargs, &block)
    end
  end
end

if defined?  OpenTelemetry::Instrumentation::Rack::Middlewares
  OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware.config[:url_quantization] = ->(path, env) {
    "HTTP #{env['REQUEST_METHOD']} #{path}"
  }
end