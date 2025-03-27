OnPush image: %r{.*project_a/.*} do
  UpdateServices :local # call method
  Push to: 'docker-registry.company.ru', auth: 'user:password' do
    UpdateServices 'https://127.0.0.1:5000/update_services', auth: 'user:password'
  end
end

OnTime minutes: 10 do
  output = []
  output << 'Hostname: ' + exec_( "curl -s --unix-socket /var/run/docker.sock http://localhost/info | jq -r '.Name'")
  output << '<example config>'
  # output << exec_('docker image prune -f')
  notify(output.join("\n")) # unless output.last =~ /Total\s+reclaimed\s+space:\s+0B/m
end
