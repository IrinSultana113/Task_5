
require "faker"
require "json"

class MovieGenerator
  LOCALE_PATH = Rails.root.join("config/locales/movies").freeze

  def initialize(seed:, locale: "en-US")
    @seed = Integer(seed)
    @locale = locale

    @config = JSON.parse(
      File.read(LOCALE_PATH.join("#{@locale}.json"), encoding: "UTF-8")
    )
  end

  def movie(index, likes_average: 4.0, reviews_average: 2.0)
    movie_random = Random.new(@seed + index)

    Faker::Config.locale = @locale == "de-DE" ? :de : :en
    Faker::Config.random = movie_random

    title = generate_title(index)

    {
      sequence: index,
      title: title,
      year: movie_random.rand(1980..2026),
      genre: @config.fetch("genres").sample(random: movie_random),
      actors: generate_actors(index),
      trailer: nil,
      likes: random_count(likes_average, index, 1),
      reviews: generate_reviews(reviews_average, index)
    }
  end

  private

  def generate_title(index)
    random = Random.new(@seed + index * 101)
    templates = @config.fetch("title_templates")
    words = @config.fetch("title_words")

    template = templates.sample(random: random)
    first = words.sample(random: random)
    second = words.sample(random: random)

    template
      .gsub("{first}", first)
      .gsub("{second}", second)
  end

  def generate_actors(index)
    random = Random.new(@seed + index * 503)
    Faker::Config.random = random

    Array.new(3) { Faker::Name.name }
  end

  def trailer_for(index, title)
  TrailerGenerator.new(
    seed: @seed,
    index: index,
    title: title
  ).call
end

  def random_count(average, index, offset)
    value = [[Float(average), 0.0].max, 10.0].min
    random = Random.new(@seed + index * 1009 + offset * 7919)

    count = value.floor
    count += 1 if random.rand < value - count

    count
  end

  
def generate_reviews(average, index)
  value = [[Float(average), 0.0].max, 10.0].min
  count_random = Random.new(@seed + index * 2017 + 2 * 7919)

  count = value.floor
  count += 1 if count_random.rand < value - count

  templates = @config.fetch("review_templates")
  parts = @config.fetch("review_parts")
  review_random = Random.new(@seed + index * 3011 + 3 * 7919)

  Array.new(count) do |review_index|
    author_random = Random.new(
      @seed + index * 4001 + review_index * 7919
    )

    Faker::Config.random = author_random

    template = templates.sample(random: review_random)

    text = template.gsub(/\{(\w+)\}/) do
      part_name = Regexp.last_match(1)
      choices = parts.fetch(part_name)
      choices.sample(random: review_random)
    end

    text = text.gsub(/(?<=[[:alpha:]])(?=[[:upper:]])/, " ")
    {
      author: Faker::Name.name,
      text: text,
    }
  end
end

end
