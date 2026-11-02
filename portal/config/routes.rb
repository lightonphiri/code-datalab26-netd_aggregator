Rails.application.routes.draw do
  match 'oai', to: 'oai#index', via: [:get, :post], as: :oai  # OAI-PMH data provider (SRS EI-4)
  # Public REST API v1 (SRS EI-6, FR-42 to FR-46); specification in public/api/v1/openapi.yaml
  scope 'api/v1', module: 'api/v1', as: 'api_v1', defaults: { format: 'json' } do
    get 'records', to: 'records#index', as: :records
    get 'records/:id', to: 'records#show', as: :record, constraints: { id: /[A-Za-z0-9_-]+/ }
    get 'institutions', to: 'institutions#index', as: :institutions
    get 'stats', to: 'stats#index', as: :stats
    get 'export.:format', to: 'exports#show', as: :export, constraints: { format: /csv|jsonl/ }, defaults: { format: nil }
    match '*path', to: 'base#preflight', via: :options
    match '*path', to: 'base#not_found', via: :all, format: false
  end
  get 'api', to: redirect('/developers/api')
  get 'api/v1', to: redirect('/developers/api')
  get 'developers/api', to: 'pages#api_docs', as: :api_docs
  namespace :admin do  # admin panel (SRS FR-36 to FR-41)
    root to: 'dashboard#index'
    get 'sign-in', to: 'sessions#new', as: :sign_in
    post 'sign-in', to: 'sessions#create'
    delete 'sign-out', to: 'sessions#destroy', as: :sign_out
    resource :password, only: %i[edit update]
    get 'sources/:id', to: 'dashboard#source', as: :source
    post 'sources/:id/run', to: 'dashboard#run', as: :run_source
    resources :problem_reports, only: %i[index show update], path: 'reports'
    resources :csv_uploads, only: %i[new create], path: 'csv'
    post 'csv/load', to: 'csv_uploads#load_file', as: :load_csv
    get 'log', to: 'events#index', as: :events
    # metadata filling: manual corrections (FR-51) and degree-level review (FR-52)
    get 'records', to: 'records#lookup', as: :record_lookup
    get 'records/:id', to: 'records#show', as: :record, constraints: { id: /[A-Za-z0-9_-]+/ }
    post 'records/:id/corrections', to: 'records#correct', as: :correct_record, constraints: { id: /[A-Za-z0-9_-]+/ }
    delete 'records/:id/corrections/:field', to: 'records#uncorrect', as: :uncorrect_record,
                                              constraints: { id: /[A-Za-z0-9_-]+/, field: /_?[a-z_]+/ }
    post 'records/:id/apply', to: 'records#apply', as: :apply_record, constraints: { id: /[A-Za-z0-9_-]+/ }
    get 'quality', to: 'quality#index', as: :quality   # per-institution metadata quality (FR-28)
    get 'review', to: 'reviews#index', as: :reviews
    post 'review/:id', to: 'reviews#decide', as: :decide_review, constraints: { id: /[A-Za-z0-9_-]+/ }
    get 'duplicates', to: 'duplicates#index', as: :duplicates   # FR-19
    get 'usage', to: 'usage#index', as: :usage   # usage analytics (FR-61)
    get 'etd-reports', to: 'etd_reports#index', as: :etd_reports   # reports for HEA (FR-63): preview, .xlsx, .pdf
    get 'etd-reports/:kind', to: 'etd_reports#show', as: :etd_report, constraints: { kind: /institution|supervisors|custom/ }
    post 'duplicates/:id', to: 'duplicates#decide', as: :decide_duplicate, constraints: { id: /[A-Za-z0-9_-]+/ }
  end
  mount Blacklight::Engine => '/'
  root to: "catalog#index"
  get "about", to: "pages#about", as: :about
  get "faq", to: "pages#faq", as: :faq
  get "developers", to: "pages#developers", as: :developers
  get "follow", to: "follow#show", as: :follow   # feeds of new additions for a search (FR-60)
  get "quality", to: "quality#index", as: :quality   # metadata quality dashboard (FR-28)
  get "catalog/:id/pdf", to: "catalog#pdf", as: :record_pdf, constraints: { id: /[A-Za-z0-9_-]+/ }  # counted download (FR-61)
  get "browse", to: "browse#index", as: :browse      # institution → faculty → department (FR-25)
  get "contribute", to: "pages#contribute", as: :contribute   # guide for institutions (FR-59)
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
