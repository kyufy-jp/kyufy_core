module KyufyCore
  # API-only base for the engine's endpoints. The host shell owns auth; this gem holds none.
  class ApplicationController < ActionController::API
    # Invalid input (empty household, members that resolve to different municipalities, …) raises
    # KyufyCore::Error. Surface it as a 422 JSON body instead of leaking a 500 HTML error page.
    rescue_from KyufyCore::Error do |error|
      render json: { error: error.message }, status: :unprocessable_content
    end
  end
end
