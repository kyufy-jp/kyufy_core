KyufyCore::Engine.routes.draw do
  resources :assessments, only: [ :create ] do
    collection do
      post :batch
      post :household
    end
  end
end
