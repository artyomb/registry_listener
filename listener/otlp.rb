
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'
require 'opentelemetry-api'

STACK_NAME = ENV['STACK_NAME'] || 'registry_listener'
SERVICE_NAME = ENV['STACK_SERVICE_NAME'] || 'registry_listener'
ENV['OTEL_RESOURCE_ATTRIBUTES'] ||= "deployment.environment=#{STACK_NAME}"

LOGGER.info OTEL_LOG_LEVEL: ENV['OTEL_LOG_LEVEL'],
            OTEL_TRACES_EXPORTER: ENV['OTEL_TRACES_EXPORTER'],
            OTEL_EXPORTER_OTLP_ENDPOINT: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'],
            SERVICE_NAME: SERVICE_NAME, STACK_NAME: STACK_NAME,
            OTEL_RESOURCE_ATTRIBUTES: ENV['OTEL_RESOURCE_ATTRIBUTES']


def flatten_hash(hash, path = [], result = {})
  hash.each do |k, v|
    path += [k]
    result[path.join('.')] = v.to_s if v.is_a?(String) || v.is_a?(Numeric)
    flatten_hash(v, path, result) if v.is_a?(Hash) || v.is_a?(Array)
    path.pop
  end
  result
end

OpenTelemetry.logger = LOGGER
def otel_initialize
  OpenTelemetry::SDK.configure do |c|
    c.service_name = SERVICE_NAME
    c.use_all # enables all instrumentation!
  end

  at_exit do
    OpenTelemetry.tracer_provider.force_flush
    OpenTelemetry.tracer_provider.shutdown
  end

  $tracer_ = OpenTelemetry.tracer_provider.tracer(SERVICE_NAME)

  otl_span "#{SERVICE_NAME} start", {
    'stack.name': ENV['STACK_NAME'],
    'stack.service.name': ENV['STACK_SERVICE_NAME'],
    'org.opencontainers.image.title': ENV['ORG_OPENCONTAINERS_IMAGE_TITLE'],
    'org.opencontainers.image.url':  ENV['ORG_OPENCONTAINERS_IMAGE_URL'],
    'org.opencontainers.image.source': ENV['ORG_OPENCONTAINERS_IMAGE_SOURCE'],
    'org.opencontainers.image.created': ENV['ORG_OPENCONTAINERS_IMAGE_CREATED'],
    'com.gitlab.ci.commt.timestamp': ENV['COM_GITLAB_CI_COMMIT_TIMESTAMP'],
    'com.gitlab.ci.tag': ENV['COM_GITLAB_CI_TAG'],
    RACK_ENV: ENV['RACK_ENV'],
    NODE_ENV: ENV['NODE_ENV'],
    SERVER_ENV: ENV['SERVER_ENV'],
  } do |span|

    # span.add_event("not-working in kibana APM", attributes:{
    #   event: 'Success',
    #   message: 'Get data from elastic Success'
    # }.transform_keys(&:to_s) )
    # span.status = OpenTelemetry::Trace::Status.error("error message here!")
  end

end

def otl_span(name, attributes = {})
  # span_ = OpenTelemetry::Trace.current_span
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
    otl_span("method: #{klass}.#{name}", {args: args.to_s, kwargs: kwargs.to_s}) do |span|
      span&.add_attributes({ args:, kwargs: })
      original_method.bind(self).call(*args, **kwargs, &block)
    end
  end
end

def otl_current_span
  yield OpenTelemetry::Trace.current_span
end

if defined?  OpenTelemetry::Instrumentation::Rack::Middlewares
  OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware.config[:url_quantization] = ->(path, env) {
    "HTTP #{env['REQUEST_METHOD']} #{path}"
  }
end