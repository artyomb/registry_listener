OnPush image: %r{.*project_a/.*} do
  Push to: 'docker-registry.company.ru', auth: 'user:password' do
    UpdateServices :local # call method
    # UpdateServices  'https://127.0.0.1:5000/update_services', auth: 'user:password'
  end
end
