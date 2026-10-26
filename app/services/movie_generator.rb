
require "faker"
require "json"

class MovieGenerator
  LOCALE_PATH = Rails.root.join("config/locales/movies").freeze

  def initialize(seed:, locale: "en-US")
    @seed = Integer(seed)
    @locale = locale
  end

  def movie(index, likes_average: 4.0, reviews_average: 2.0)
    config = JSON.parse(
      File.read(LOCALE_PATH.join("#{@locale}.json"), encoding: "UTF-8")
    )

    movie_random = Random.new(@seed + index)
    trailer_files = %w[city_night.mp4 nature.mp4 action.mp4]
    trailer = trailer_files[Random.new(@seed + index * 997).rand(trailer_files.length)]
    Faker::Config.locale = @locale.split("-").first.downcase.to_sym
    Faker::Config.random = movie_random

    title = Faker::Movie.title
    year = movie_random.rand(1980..2026)
    genre = config.fetch("genres").sample(random: movie_random)
    actors = Array.new(3) { Faker::Name.name }

    {
      sequence: index,
      title: title,
      year: year,
      genre: genre,
      actors: actors,
      trailer: "/trailers/#{trailer}",
      likes: random_count(likes_average, index, 1),
      reviews: generate_reviews(reviews_average, index)
    }
  end

  private

  def random_count(average, index, offset)
    value = [[Float(average), 0.0].max, 10.0].min
    random = Random.new(@seed + index * 1009 + offset * 7919)
    count = value.floor
    count += 1 if random.rand < value - count
    count
  end

  def generate_reviews(average, index)
    value = [[Float(average), 0.0].max, 10.0].min
    random = Random.new(@seed + index * 2017 + 2 * 7919)
    count = value.floor
    count += 1 if random.rand < value - count

    review_random = Random.new(@seed + index * 3011 + 3 * 7919)
    Faker::Config.random = review_random

    Array.new(count) do
      {
        author: Faker::Name.name,
        text: Faker::Lorem.paragraph(sentence_count: 2)
      }
    end
  end
end


