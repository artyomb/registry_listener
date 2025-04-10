require 'async'
require 'async/semaphore'
require 'open3'

# list docker service tasks
# docker service ps graph_node_graph_solve_api --filter="desired-state=running" --no-trunc --format="{{ .ID }}"

# docker task container
# docker inspect 1uu75an0sp169tkgezslmi9dn | jq -r .[0].Status.ContainerStatus.ContainerID

# container image id
# docker container inspect bafa6b18af7a394113e761312859e27ca27c33c8bfe3e41c9deb8f87fa4b53ca | jq -r .[0].Image

# docker task image sha
# docker container inspect $(docker inspect 1uu75an0sp169tkgezslmi9dn | jq -r .[0].Status.ContainerStatus.ContainerID) | jq -r .[0].Image

$containers_cache = {}

module UpdateService
  extend self
  UPDATE = Async::Semaphore.new(1)

  async otl_def def list_service_tasks(ctx, service_name)
    exec_("docker --context #{ctx} service ps --filter=\"desired-state=running\" --no-trunc --format \"{{.ID}}\" #{service_name}").lines.map(&:strip).uniq
  end

  async otl_def def get_task_image_digest(ctx, task_name)
    exec_("docker  --context #{ctx} container inspect $(docker inspect #{task_name} | jq -r .[0].Status.ContainerStatus.ContainerID) | jq -r .[0].Image")
  end

  async otl_def def list_services(ctx)
    exec_("docker --context #{ctx} service ls --format {{.Name}}\\\|{{.Image}}").lines.map { _1.split('|').map(&:strip) }.to_h
  end

  async otl_def def list_containers(ctx)
    # containers = JSON exec_ %{docker --context #{ctx} ps -q | xargs -n1 docker inspect | jq -s 'map(.[0] | {ID: .Id, Name: .Name, ConfigImage: .Config.Image, Image: .Image})'}
    containers = JSON exec_ %(docker --context #{ctx} ps --format '{"ID":"{{.ID}}","Name":"{{.Names}}","Image":"{{.Image}}"}' | jq -s)

    ids = containers.map { _1['ID'] }
    $containers_cache.select! {|k,v| ids.include? k } # delete obsolete containers

    containers.each do |c|
      otl_current_span { _1.add_event('inspect container', attributes: { event: 'Success', message: "C_Name: #{c['Name']}, C_ID:#{c['ID']}"}.transform_keys(&:to_s) ) }

      $containers_cache[c['ID']] ||= begin
        JSON exec_ %(docker --context #{ctx} inspect #{c['ID']} | jq -r .[0] )
      end

      if $containers_cache[c['ID']]
        $containers_cache[c['ID']][:ImageRepoDigests] ||= begin
          image = JSON exec_ %(docker --context #{ctx} image inspect #{c['Image']} | jq -r .[0])
          image['RepoDigests'][0][/sha256:.{64}/]
        end
      end
    end
    $containers_cache
  end

  async otl_def def service_image_digest(ctx, service_name)
    exec_("docker --context #{ctx} service inspect --format \"{{.Spec.TaskTemplate.ContainerSpec.Image}}\" #{service_name} | awk -F'@' '{print $2}'").strip
  end

  async otl_def def update_service(ctx, c_name, service_name, image)
    notify "Self update #{c_name}: \n#{image}" if image =~ /dtorry\/registry_listener/ && ctx == 'ctx--var-run-docker-sock'

    exec_("docker --context #{ctx} service update --force #{service_name} --image #{image} --with-registry-auth") do |output, exitstatus|
      if exitstatus.zero? && output !~ /rollback/
        notify "Service converged #{c_name}: #{service_name}, image: #{image}"
      else
        notify "Failed update service #{c_name}: #{service_name}, image: #{image}"
      end
    end
  end

  async otl_def def pull_image_digest(ctx, image)
    pull_response = exec_("docker --context #{ctx} pull #{image}")
    pull_response = pull_response.lines.map { _1.scan(/([^:]+):\s*(.*)/).flatten }.to_h
    pull_response['Digest']
  end

  otl_def def update_services(update_image = nil, update_digest = nil)
    return 'Update already in progress ...' if UPDATE.blocking? && !update_image

    otl_span :update_services, attributes: {update_image:, update_digest:} do |span|

      UPDATE.acquire do
        span.add_event('start updating', attributes: { event: 'Success', message: 'Get data from elastic Success'}.transform_keys(&:to_s) )

        HOSTS.map_async do |ctx, semaphore, _host, c_name|
          semaphore.acquire do
            containers, services = [list_containers(ctx), list_services(ctx)].map(&:wait)

            services.map_async do |name, service_image|
              c_list = containers.values.select { _1['Name'] =~ /^\/#{name}/ }
              c_digests = c_list.map { _1[:ImageRepoDigests] }

              if update_image
                next "Skipping(update_image) #{c_name}: #{service_image}" unless service_image =~ /#{update_image}/
              else
                next "Skipping: #{service_image}" unless service_image =~ IMAGE_FILTER
              end
              # task_names = list_service_tasks(ctx, name).wait
              # task_names.each do |task_name|
              #   digest = get_task_image_digest(ctx, task_name).wait
              #   p "#{c_name}: #{name} #{service_image} on #{_host} digest: #{digest}"
              # end

              latest_digest = pull_image_digest(ctx, service_image).wait

              if c_digests.empty? || c_digests.include?(latest_digest)
                "No update required for #{c_name}: #{name} #{service_image} on #{_host}: digest #{c_digests}"
              else
                update_service(ctx, c_name, name, service_image).wait
                "Updating #{c_name}: #{name} #{service_image} on #{_host} to #{c_digests}. Previous digest: #{c_digests}"
              end
            end
          end
        end.flatten
      end

    end
  end

end
