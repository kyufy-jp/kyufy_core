KyufyCore::Engine.routes.draw do
  resources :assessments, only: [ :create ]
end
