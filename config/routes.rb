Rails.application.routes.draw do
  # Health check endpoint
  get '/health', to: 'health#show'
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  # Defines the root path route ("/")
  # root "articles#index"
end
