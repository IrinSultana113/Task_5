
require "fileutils"
require "digest"
require "open3"

class TrailerGenerator
  WIDTH = 640
  HEIGHT = 360
  DURATION = 6.0
  FPS = 24
  CLIP_COUNT = 4
  CLIP_DURATION = 1.5
  CLIP_FRAMES = (CLIP_DURATION * FPS).to_i

  SOURCES = %w[
    public/trailers/optimized/action.mp4
    public/trailers/optimized/car_chase.mp4
    public/trailers/optimized/city_night.mp4
    public/trailers/optimized/city_timelapse.mp4
    public/trailers/optimized/nature.mp4
    public/trailers/optimized/night_cars.mp4
    public/trailers/optimized/police_chase.mp4
    public/trailers/optimized/rain.mp4
    public/trailers/optimized/rainy_city.mp4
    public/trailers/optimized/rainy_street.mp4
    public/trailers/optimized/space.mp4
    public/trailers/optimized/urban_chase.mp4
    public/trailers/optimized/fire.mp4
    public/trailers/optimized/mountain.mp4
    public/trailers/optimized/ocean.mp4
  ].freeze

  SOURCE_DURATIONS = {
    "action.mp4" => 7.375,
    "car_chase.mp4" => 8.958333,
    "city_night.mp4" => 9.083333,
    "city_timelapse.mp4" => 7.978333,
    "fire.mp4" => 10.041667,
    "mountain.mp4" => 18.625,
    "nature.mp4" => 8.0,
    "night_cars.mp4" => 6.549,
    "ocean.mp4" => 6.208333,
    "police_chase.mp4" => 10.083333,
    "rain.mp4" => 6.041667,
    "rainy_city.mp4" => 16.583333,
    "rainy_street.mp4" => 9.791667,
    "space.mp4" => 8.208333,
    "urban_chase.mp4" => 10.083333
  }.freeze

  def initialize(seed:, index:, title:)
    @seed = Integer(seed)
    @index = Integer(index)
    @title = title.to_s

    raise ArgumentError, "Index must be non-negative" if @index.negative?

    @random = Random.new(@seed + @index * 997)
    @root = Rails.root
    @source_dir = @root.join("public/trailers")
    @audio_dir = @source_dir.join("audio")
    @output_dir = @source_dir.join("generated")
  end

  def call
    sources = selected_sources

    sources.each do |source|
      path = @root.join(source)
      raise "Missing trailer footage: #{path}" unless path.file?
    end

    %w[cinematic.mp3 whoosh.mp3 impact.mp3].each do |file|
      path = @audio_dir.join(file)
      raise "Missing trailer audio: #{path}" unless path.file?
    end

    FileUtils.mkdir_p(@output_dir)

    key = Digest::SHA256.hexdigest(
      "#{@seed}:#{@index}:#{@title}:trailer-v10"
    )[0, 24]

    output = @output_dir.join("#{key}.mp4")

    if output.file? && output.size.positive?
      return "/trailers/generated/#{key}.mp4"
    end

    ffmpeg = ENV.fetch("FFMPEG_PATH", "ffmpeg")
    font = font_path

    work_dir = @root.join("tmp/trailer_work", key)
    FileUtils.mkdir_p(work_dir)

    text_path = work_dir.join("title.txt")
    File.write(text_path, safe_text(@title), encoding: "UTF-8")

    text_filter_path = text_path.to_s.tr("\\", "/").gsub(":", "\\:")
    font_filter = font.tr("\\", "/").gsub(":", "\\:")

    filters = []

    CLIP_COUNT.times do |i|
      source = sources[i]
      filename = File.basename(source)
      source_duration = SOURCE_DURATIONS.fetch(filename)

      speed = @random.rand(0.90..1.10).round(2)
      source_segment_duration = CLIP_DURATION * speed
      max_start = [source_duration - source_segment_duration, 0.0].max

      # Select a different segment from each source.
      start_time = @random.rand(0.0..max_start).round(3)

      brightness = @random.rand(-0.06..0.04).round(3)
      contrast = @random.rand(1.05..1.20).round(2)
      saturation = @random.rand(0.80..1.25).round(2)
      zoom = @random.rand(1.02..1.12).round(3)

      scaled_width = (WIDTH * zoom).ceil
      scaled_height = (HEIGHT * zoom).ceil

      filters << (
        "[#{i}:v]" \
        "trim=start=#{start_time}:duration=#{source_segment_duration.round(4)}," \
        "setpts=PTS-STARTPTS," \
        "setpts=PTS/#{speed}," \
        "fps=#{FPS}," \
        "scale=#{scaled_width}:#{scaled_height}:" \
        "force_original_aspect_ratio=increase," \
        "crop=#{WIDTH}:#{HEIGHT}:" \
        "x='(in_w-out_w)/2':y='(in_h-out_h)/2'," \
        "eq=contrast=#{contrast}:brightness=#{brightness}:" \
        "saturation=#{saturation}," \
        "setsar=1,format=yuv420p," \
        "trim=end_frame=#{CLIP_FRAMES}," \
        "settb=1/#{FPS}," \
        "setpts=N," \
        "setpts=PTS-STARTPTS[v#{i}]"
      )
    end

    title_size = @random.rand(32..44)
    title_y = [
      "(h-text_h)/4",
      "(h-text_h)/2",
      "h-text_h-(h-text_h)/4"
    ].sample(random: @random)

    filters << (
      "[v0][v1][v2][v3]concat=n=4:v=1:a=0," \
      "trim=duration=#{DURATION}," \
      "settb=1/#{FPS},setpts=PTS-STARTPTS," \
      "drawtext=fontfile='#{font_filter}':" \
      "textfile='#{text_filter_path}':" \
      "fontcolor=white:fontsize=#{title_size}:" \
      "borderw=2:bordercolor=black@0.8:" \
      "shadowcolor=black@0.7:shadowx=2:shadowy=2:" \
      "x=(w-text_w)/2:y=#{title_y}:" \
      "alpha='if(lt(t,0.25),t/0.25,if(gt(t,5.5),(6-t)/0.5,1))'," \
      "fade=t=in:st=0:d=0.25," \
      "fade=t=out:st=5.5:d=0.5[vout]"
    )

    music_volume = @random.rand(0.20..0.32).round(2)
    whoosh_delay = @random.rand(300..1500)
    impact_delay = @random.rand(2800..4300)

    filters << (
      "[4:a]atrim=duration=#{DURATION}," \
      "asetpts=PTS-STARTPTS,volume=#{music_volume}[music]"
    )

    filters << (
      "[5:a]atrim=duration=1," \
      "asetpts=PTS-STARTPTS,volume=0.65," \
      "adelay=#{whoosh_delay}|#{whoosh_delay}[whoosh]"
    )

    filters << (
      "[6:a]atrim=duration=1.5," \
      "asetpts=PTS-STARTPTS,volume=0.75," \
      "adelay=#{impact_delay}|#{impact_delay}[impact]"
    )

    filters << (
      "[music][whoosh][impact]" \
      "amix=inputs=3:duration=first:normalize=0," \
      "atrim=duration=#{DURATION}," \
      "asetpts=PTS-STARTPTS[aout]"
    )

    args = [
      ffmpeg, "-y",
      "-filter_complex_threads", "1",
      "-threads", "1"
    ]

    sources.each do |source|
      args.concat(["-i", @root.join(source).to_s])
    end

    args.concat([
      "-stream_loop", "-1",
      "-i", @audio_dir.join("cinematic.mp3").to_s,
      "-i", @audio_dir.join("whoosh.mp3").to_s,
      "-i", @audio_dir.join("impact.mp3").to_s,
      "-filter_complex", filters.join(";"),
      "-map", "[vout]",
      "-map", "[aout]",
      "-t", DURATION.to_s,
      "-r", FPS.to_s,
      "-c:v", "libx264",
      "-threads", "1",
      "-preset", "ultrafast",
      "-crf", "28",
      "-pix_fmt", "yuv420p",
      "-c:a", "aac",
      "-b:a", "96k",
      "-movflags", "+faststart",
      output.to_s
    ])

    _stdout, stderr, status = Open3.capture3(*args)

    unless status.success? && output.file? && output.size.positive?
      FileUtils.rm_f(output)
      raise "FFmpeg trailer generation failed: #{stderr.lines.last(20).join}"
    end

    "/trailers/generated/#{key}.mp4"
  ensure
    FileUtils.rm_rf(work_dir) if defined?(work_dir) && work_dir
  end

  private

  def selected_sources
    combinations = SOURCES.combination(CLIP_COUNT).to_a
    position = (@seed.abs + @index * 997) % combinations.length
    combinations[position].shuffle(
      random: Random.new(@seed + @index * 997)
    )
  end

  def safe_text(text)
    text.to_s.gsub(/[\r\n]/, " ").strip
  end

  def font_path
    candidates =
      if Gem.win_platform?
        [
          "C:/Windows/Fonts/ARIALBD.TTF",
          "C:/Windows/Fonts/ARIAL.TTF"
        ]
      else
        [
          "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        ]
      end

    font = candidates.find { |path| File.file?(path) }
    raise "No supported font found" unless font

    font
  end
end