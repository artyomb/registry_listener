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

    LOGGER.info "List containers in: containers: #{containers.size}, $containers_cache: #{$containers_cache.size}"

    containers.each_with_index do |c, index|
      LOGGER.info "containers: #{index}/#{containers.size} #{c['ID']} #{c['Name']}"

      otl_current_span { _1.add_event('inspect container', attributes: { event: 'Success', message: "C_Name: #{c['Name']}, C_ID:#{c['ID']}"}.transform_keys(&:to_s) ) }

      $containers_cache[c['ID']] ||= JSON exec_ %(docker --context #{ctx} inspect #{c['ID']} | jq -r .[0] )

      if $containers_cache[c['ID']]
        $containers_cache[c['ID']][:ImageRepoDigests] ||= begin
          image = JSON exec_ %(docker --context #{ctx} image inspect #{$containers_cache[c['ID']]['Image']} | jq -r .[0])
          image['RepoDigests'].map { _1[/sha256:.{64}/] }
        end
      end
    end
    LOGGER.info "List containers done: containers: #{containers.size}, $containers_cache: #{$containers_cache.size}"
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

  async otl_def def manifest_image_digest(ctx, image)
    manifests = JSON.parse `docker --context #{ctx} manifest inspect --verbose #{image}`
    manifest = manifests.find do |m|
      m['Descriptor']['platform']['os'] == 'linux' && m['Descriptor']['platform']['architecture'] == 'amd64'
    end
    manifest['Descriptor']['digest'] if manifest
  end

  async otl_def def hub_image_digest(image)
    repo, tag = image.split(':')
    tag = 'latest' unless tag && !tag.empty?

    # Only check Docker Hub images. Images on other registries have a '.' in the name.
    return nil if repo.split('/')[0].include?('.')

    # Official images (e.g., 'ubuntu') don't have a '/' and are in the 'library' namespace.
    full_repo = repo.include?('/') ? repo : "library/#{repo}"

    puts "https://hub.docker.com/v2/repositories/#{full_repo}/tags/#{tag}/"

    manifest = exec_ "curl -k -s 'https://hub.docker.com/v2/repositories/#{full_repo}/tags/#{tag}/'"
    manifest = JSON manifest, symbolize_names: true

    # Can't get digest from manifest.list
    # only for application/vnd.docker.container.image.v1+json
    return nil if manifest[:media_type] == "application/vnd.docker.distribution.manifest.list.v2+json"

    digest =  manifest[:digest] || manifest[:images].find { |i| i[:architecture] == 'amd64' }[:digest] rescue nil
    digest.to_s =~ /sha256:.{64}/ ? digest : nil
  end

  otl_def def update_services(update_image = nil, update_digest = nil)
    return 'Update already in progress ...' if UPDATE.blocking? && !update_image

    otl_span :update_services, attributes: {update_image:, update_digest:} do |span|

      UPDATE.acquire do
        span.add_event('start updating', attributes: { event: 'Success', message: 'Get data from elastic Success'}.transform_keys(&:to_s) )

        HOSTS.map_async do |ctx, semaphore, _host, c_name|
          semaphore.acquire do
            containers, services = [list_containers(ctx), list_services(ctx)].map(&:wait)
            LOGGER.info "Update acquire: Containers: #{containers.size}, services: #{services.size}"

            services.map_async do |name, service_image|
              LOGGER.info "Update #{c_name}: #{name}, image: #{service_image}"

              c_list = containers.values.select { _1['Name'] =~ /^\/#{name}/ }
              c_digests = c_list.map { _1[:ImageRepoDigests] }.flatten

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

              # latest_digest = hub_image_digest(service_image).wait rescue nil
              # latest_digest ||= manifest_image_digest(ctx, service_image).wait rescue nil
              latest_digest ||= pull_image_digest(ctx, service_image).wait

              LOGGER.info "Latest digest: #{latest_digest}"

              if c_digests.empty? || c_digests.include?(latest_digest)
                LOGGER.info "No update required for #{c_name}: #{name} #{service_image} on #{_host}: digest #{c_digests}"
                "No update required for #{c_name}: #{name} #{service_image} on #{_host}: digest #{c_digests}"
              else
                LOGGER.info "Updating #{c_name}: #{name} #{service_image} on #{_host} to #{latest_digest}. Previous digest: #{c_digests}"
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
