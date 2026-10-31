Rails.application.routes.draw do
  match 'oai', to: 'oai#index', via: [:get, :post], as: :oai  # OAI-PMH data provider (SRS EI-4)
  mount Blacklight::Engine => '/'
  root to: "catalog#index"
  get "about", to: "pages#about", as: :about
  get "faq", to: "pages#faq", as: :faq
  get "developers", to: "pages#developers", as: :developers
  get "credits", to: "pages#credits", as: :credits
  post "report-problem", to: "problem_reports#create", as: :problem_reports
  concern :searchable, Blacklight::Routes::Searchable.new

  resource :catalog, only: [], as: 'catalog', path: '/catalog', controller: 'catalog' do
    concerns :searchable
  end

  concern :exportable, Blacklight::Routes::Exportable.new

  resources :solr_documents, only: [:show], path: '/catalog', controller: 'catalog' do
    concerns :exportable
  end

  resources :bookmarks, only: [:index, :update, :create, :destroy] do
    concerns :exportable

    collection do
      delete 'clear'
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
