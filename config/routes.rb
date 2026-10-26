Rails.application.routes.draw do
  root "movies#index"
  get "movies", to: "movies#index"
  get "api/movies", to: "movies#data"
end