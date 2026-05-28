route_set = Rails.application.routes.routes

unless route_set.any? {|route| route.path.spec.to_s == '/dev_integrations/github/webhook'}
  Rails.application.routes.append do
    post '/dev_integrations/github/webhook', to: 'dev_integrations/github_webhooks#create'
  end
end

unless route_set.any? {|route| route.path.spec.to_s == '/dev_integrations/gitlab/webhook'}
  Rails.application.routes.append do
    post '/dev_integrations/gitlab/webhook', to: 'dev_integrations/gitlab_webhooks#create'
  end
end

unless route_set.any? {|route| route.path.spec.to_s == '/dev_integrations/bitbucket/webhook'}
  Rails.application.routes.append do
    post '/dev_integrations/bitbucket/webhook', to: 'dev_integrations/bitbucket_webhooks#create'
  end
end

unless route_set.any? {|route| route.path.spec.to_s == '/projects/:project_id/redmine_dev_integration/settings(.:format)'}
  Rails.application.routes.append do
    resources :projects, only: [] do
      scope module: :projects do
        resources :redmine_dev_integration, only: %i[new edit create update destroy], controller: :redmine_dev_integration do
          patch :settings, on: :collection
          post :trigger_provider_sync, on: :member
          post :retry_provider_event, on: :member
          post :register_webhook, on: :member
          get :load_repositories, on: :collection
          post :create_user_mapping, on: :collection
          delete :destroy_user_mapping, on: :collection
        end
      end
      get 'deployment_overview', to: 'projects/deployment_overview#index'
      get 'releases', to: 'projects/releases#index'
      get 'dora_metrics', to: 'projects/dora_metrics#show'
    end
  end
end


# OAuth routes
unless route_set.any? {|route| route.path.spec.to_s == '/dev_integrations/github/oauth/start'}
  Rails.application.routes.append do
    get '/dev_integrations/github/oauth/start', to: 'dev_integrations/oauth#start', defaults: {provider: 'github'}
    get '/dev_integrations/github/oauth/callback', to: 'dev_integrations/oauth#callback', defaults: {provider: 'github'}
    post '/dev_integrations/github/oauth/disconnect', to: 'dev_integrations/oauth#disconnect', defaults: {provider: 'github'}
    get '/dev_integrations/gitlab/oauth/start', to: 'dev_integrations/oauth#start', defaults: {provider: 'gitlab'}
    get '/dev_integrations/gitlab/oauth/callback', to: 'dev_integrations/oauth#callback', defaults: {provider: 'gitlab'}
    post '/dev_integrations/gitlab/oauth/disconnect', to: 'dev_integrations/oauth#disconnect', defaults: {provider: 'gitlab'}
    get '/dev_integrations/bitbucket/oauth/start', to: 'dev_integrations/oauth#start', defaults: {provider: 'bitbucket'}
    get '/dev_integrations/bitbucket/oauth/callback', to: 'dev_integrations/oauth#callback', defaults: {provider: 'bitbucket'}
    post '/dev_integrations/bitbucket/oauth/disconnect', to: 'dev_integrations/oauth#disconnect', defaults: {provider: 'bitbucket'}
  end
end
