KyufyCore::Engine.routes.draw do
  resources :assessments, only: [ :create ] do
    post :batch, on: :collection
  end
end
