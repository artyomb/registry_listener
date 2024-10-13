OnPush image: %r{.*project_a/.*} do
  UpdateServices :local # call method
  Push to: 'docker-registry.company.ru', auth: 'user:password' do
    UpdateServices 'https://127.0.0.1:5000/update_services', auth: 'user:password'
  end
end

OnTime minutes: 10 do
  output = exec_ 'docker image prune -f'
  notify output
end
