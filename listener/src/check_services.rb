module CheckServices
  extend self

  otl_def def get_services_status(ctx)
    exec_ %{docker --context #{ctx} service ls --format "{{.ID}}\t{{.Name}}\t{{.Replicas}}\t{{.Ports}}\t{{.Image}}" |
              grep -E "\s0/[0-9]+" |
                  while read -r line; do
                    echo "$line"
                    service_id=$(echo "$line" | awk '{print $1}')
                    docker --context #{ctx} service ps --format "{{.Error}}" "$service_id" | grep -v "^$"
                  done}
  end


  otl_def def check_services
    HOSTS.map_async do |ctx, semaphore, _host|
      semaphore.acquire do
        result = get_services_status(ctx)
        otl_current_span { _1.add_attributes "result-#{ctx}" => result }

        notify "Service status:\n#{result}" unless result.empty?
      end
    end
  end
end
