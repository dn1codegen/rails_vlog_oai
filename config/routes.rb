Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "posts#index"

  resource :registration, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resource :profile, only: %i[show edit update] do
    get :export_videos
    post :import_videos
  end
  patch "profile/posts/:id/visibility", to: "profiles#update_post_visibility", as: :profile_post_visibility

  resources :posts, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    get :youtube_options, on: :collection
    resource :reaction, only: [ :create ], module: :posts
    resources :comments, only: [ :create, :edit, :update, :destroy ]
  end
end
