require 'rest-client'
require 'async'
require 'async/semaphore'
require 'logger'
require 'open3'

module UpdateService
  extend self
  @update = Async::Semaphore.new(1)

  async otl_def def list_services(ctx)
    exec_("docker --context #{ctx} service ls --format {{.Name}}\\\|{{.Image}} | grep latest").lines.map{ _1.split('|').map(&:strip) }.to_h
  end

  async otl_def def service_image_digest(ctx, service_name)
    exec_("docker --context #{ctx} service inspect --format \"{{.Spec.TaskTemplate.ContainerSpec.Image}}\" #{service_name} | cut -d'@' -f2;").strip
  end

  async otl_def def update_service(ctx, service_name)
    exec_("docker --context #{ctx} service update --force #{service_name}") # --image #{image}
  end

  async otl_def def image_digest(ctx, image)
    pull_response = exec_("docker --context #{ctx} pull #{image}")
    pull_response = pull_response.lines.map{ _1.scan(/([^:]+):\s*(.*)/).flatten }.to_h
    pull_response['Digest']
  end

  otl_def def update_services()
    return 'Update already in progress ...' if @update.blocking?

    @update.acquire do
      HOSTS.map_async do |ctx, semaphore, _host|
        semaphore.acquire do
          list_services(ctx).wait.map_async do |name, image|
            next "Skipping: #{image}" unless image =~ IMAGE_FILTER

            latest_digest= image_digest ctx, image
            service_digest = service_image_digest ctx, name

            if service_digest.wait != latest_digest.wait
              update_service(ctx, name).wait
              "Updating #{name} on #{_host}"
            else
              "No update required for #{name} on #{_host}: digest #{service_digest}"
            end
          end
        end
      end.flatten
    end
  end

end
