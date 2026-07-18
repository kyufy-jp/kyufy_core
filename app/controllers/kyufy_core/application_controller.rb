module KyufyCore
  # API-only base for the engine's endpoints. The host shell owns auth; this gem holds none.
  class ApplicationController < ActionController::API
  end
end
