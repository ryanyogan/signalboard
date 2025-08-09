Rails.application.routes.draw do
  root "projects#index"

  resources :projects
  resources :notifications

  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token
  resources :registrations, only: [ :new, :create ]

  get "up" => "rails/health#show", as: :rails_health_check
end
