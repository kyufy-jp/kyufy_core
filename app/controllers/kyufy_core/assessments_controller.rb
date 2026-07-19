module KyufyCore
  # Optional mountable JSON API (§7). POST /assessments with a profile returns the JSON mirror
  # of KyufyCore.assess — prefixed IDs only, never raw PKs. No auth here (the shell handles it).
  class AssessmentsController < ApplicationController
    PROFILE_FIELDS = %i[age residence household_size prior_year_income_jpy employment target].freeze

    def create
      result = KyufyCore.assess(
        profile: profile_params.to_h,
        categories: params[:categories],
        plain_language: plain_language_param
      )
      render json: { assessments: result.as_json }, status: :ok
    end

    # POST /assessments/batch with `profiles: [ {...}, {...} ]` returns one assessment set per
    # profile (e.g. a whole 世帯), in input order.
    def batch
      results = KyufyCore.assess_batch(
        profiles: batch_profile_params,
        categories: params[:categories],
        plain_language: plain_language_param
      )
      render json: { results: results.map { |result| { assessments: result.as_json } } }, status: :ok
    end

    private

    def profile_params
      params.fetch(:profile, {}).permit(*PROFILE_FIELDS)
    end

    def batch_profile_params
      Array(params[:profiles]).map { |profile| profile.permit(*PROFILE_FIELDS).to_h }
    end

    def plain_language_param
      ActiveModel::Type::Boolean.new.cast(params[:plain_language])
    end
  end
end
