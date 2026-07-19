module KyufyCore
  # Optional mountable JSON API (§7). POST /assessments with a profile returns the JSON mirror
  # of KyufyCore.assess — prefixed IDs only, never raw PKs. No auth here (the shell handles it).
  class AssessmentsController < ApplicationController
    def create
      result = KyufyCore.assess(
        profile: profile_params.to_h,
        categories: params[:categories],
        plain_language: ActiveModel::Type::Boolean.new.cast(params[:plain_language])
      )
      render json: { assessments: result.as_json }, status: :ok
    end

    private

    def profile_params
      params.fetch(:profile, {}).permit(
        :age, :residence, :household_size, :prior_year_income_jpy, :employment, :target
      )
    end
  end
end
