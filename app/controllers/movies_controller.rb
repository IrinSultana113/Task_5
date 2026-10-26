
class MoviesController < ApplicationController
  def index
  end

  def data
    seed = params[:seed].presence || "589334323"
    locale = params[:locale].presence || "en-US"

    allowed_locales = %w[en-US de-DE]
    unless allowed_locales.include?(locale)
      return render json: { error: "Unsupported locale" },
                    status: :bad_request
    end

    page = [(params[:page] || 1).to_i, 1].max
    per_page = [[(params[:per_page] || 20).to_i, 1].max, 100].min

    likes_average = params.fetch(:likes_average, 4.0)
    reviews_average = params.fetch(:reviews_average, 2.0)

    generator = MovieGenerator.new(seed: seed, locale: locale)
    start_index = (page - 1) * per_page

    movies = (start_index...(start_index + per_page)).map do |index|
      generator.movie(
        index,
        likes_average: likes_average,
        reviews_average: reviews_average
      )
    end

    render json: {
      movies: movies,
      page: page,
      per_page: per_page
    }
  rescue ArgumentError, Errno::ENOENT, JSON::ParserError
    render json: { error: "Invalid parameters" }, status: :bad_request
  end
end
