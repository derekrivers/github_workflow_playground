Rails.application.routes.draw do
  resources :notes, only: %i[index show create] do
    collection do
      get :ping
    end
  end
end
