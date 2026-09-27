Rails.application.routes.draw do
  resources :notes, only: %i[index show create]
end
