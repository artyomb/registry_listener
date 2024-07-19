require 'async'
require 'async/semaphore'
require 'open3'

module UpdateService
  extend self
  UPDATE = Async::Semaphore.new(1)

  async otl_def def list_services(ctx)
    exec_("docker --context #{ctx} service ls --format {{.Name}}\\\|{{.Image}}").lines.map { _1.split('|').map(&:strip) }.to_h
  end

  async otl_def def service_image_digest(ctx, service_name)
    exec_("docker --context #{ctx} service inspect --format \"{{.Spec.TaskTemplate.ContainerSpec.Image}}\" #{service_name} | awk -F'@' '{print $2}'").strip
  end

  async otl_def def update_service(ctx, service_name, image)
    notify "Self update: \n#{image}" if image =~ /dtorry\/registry_listener/ && ctx == 'ctx--var-run-docker-sock'

    exec_("docker --context #{ctx} service update --force #{service_name} --image #{image}") do |output, exitstatus|
      if exitstatus.zero?
        notify "Service converged: #{service_name}, image: #{image}"
      else
        notify "Failed update service: #{service_name}, image: #{image}"
      end
    end
  end

  async otl_def def image_digest(ctx, image)
    pull_response = exec_("docker --context #{ctx} pull #{image}")
    pull_response = pull_response.lines.map { _1.scan(/([^:]+):\s*(.*)/).flatten }.to_h
    pull_response['Digest']
  end

  otl_def def update_services(update_image = nil, update_digest = nil)
    return 'Update already in progress ...' if UPDATE.blocking? && !update_image

    otl_span :update_services, attributes: {update_image:, update_digest:} do |span|

      UPDATE.acquire do
        span.add_event('start updating', attributes: { event: 'Success',message: 'Get data from elastic Success'}.transform_keys(&:to_s) )

        HOSTS.map_async do |ctx, semaphore, _host|
          semaphore.acquire do
            list_services(ctx).wait.map_async do |name, service_image|
              if update_image
                next "Skipping(update_image): #{service_image}" unless service_image =~ /#{update_image}/
              else
                next "Skipping: #{service_image}" unless service_image =~ IMAGE_FILTER
              end

              latest_digest, service_digest = [image_digest(ctx, service_image), service_image_digest(ctx, name)].map(&:wait)
              if service_digest != latest_digest
                image_with_digest = "#{service_image}@#{latest_digest}"
                update_service(ctx, name, image_with_digest).wait
                "Updating #{name} #{service_image} on #{_host} to #{image_with_digest}. Previous digest: #{service_digest}"
              else
                "No update required for #{name} #{service_image} on #{_host}: digest #{service_digest}"
              end
            end
          end
        end.flatten
      end

    end
  end

end
