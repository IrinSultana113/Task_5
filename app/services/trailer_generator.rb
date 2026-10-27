
require "fileutils"
require "digest"
require "open3"

class TrailerGenerator
  WIDTH = 640
  HEIGHT = 360
  DURATION = 6.0
  FPS = 24
  CLIP_COUNT = 3
  CLIP_DURATION = 13.0 / 6.0
  TRANSITION_DURATION = 0.2

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
  ].freeze

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
      "#{@seed}:#{@index}:#{@title}:trailer-v6"
    )[0, 24]

    output = @output_dir.join("#{key}.mp4")

    if output.file? && output.size.positive?
      return "/trailers/generated/#{key}.mp4"
    end

    ffmpeg = ENV.fetch("FFMPEG_PATH", "ffmpeg")
    font = windows_font_path

    work_dir = @root.join("tmp/trailer_work", key)
    FileUtils.mkdir_p(work_dir)

    text_path = work_dir.join("title.txt")
    File.write(text_path, safe_text(@title), encoding: "UTF-8")

    text_filter_path = text_path.to_s.tr("\\", "/").gsub(":", "\\:")
    font_filter = font.tr("\\", "/").gsub(":", "\\:")

    filters = []

    CLIP_COUNT.times do |i|
      brightness = @random.rand(-0.06..0.04).round(3)
      contrast = @random.rand(1.05..1.20).round(2)
      saturation = @random.rand(0.85..1.25).round(2)
      zoom = @random.rand(1.02..1.10).round(3)
      speed = @random.rand(0.90..1.10).round(2)

      scaled_width = (WIDTH * zoom).ceil
      scaled_height = (HEIGHT * zoom).ceil

      filters << (
        "[#{i}:v]" \
        "trim=duration=#{(CLIP_DURATION * speed).round(4)}," \
        "setpts=PTS/#{speed}," \
        "fps=#{FPS}," \
        "scale=#{scaled_width}:#{scaled_height}:" \
        "force_original_aspect_ratio=increase," \
        "crop=#{WIDTH}:#{HEIGHT}," \
        "eq=contrast=#{contrast}:brightness=#{brightness}:" \
        "saturation=#{saturation}," \
        "setsar=1,format=yuv420p," \
        "settb=AVTB,setpts=PTS-STARTPTS[v#{i}]"
      )
    end

    filters << (
      "[v0][v1]xfade=transition=fade:" \
      "duration=#{TRANSITION_DURATION}:offset=1.9667[x1]"
    )

    filters << (
      "[x1][v2]xfade=transition=fade:" \
      "duration=#{TRANSITION_DURATION}:offset=3.9333," \
      "trim=duration=#{DURATION},setpts=PTS-STARTPTS," \
      "drawtext=fontfile='#{font_filter}':" \
      "textfile='#{text_filter_path}':" \
      "fontcolor=white:fontsize=40:" \
      "borderw=2:bordercolor=black@0.8:" \
      "shadowcolor=black@0.7:shadowx=2:shadowy=2:" \
      "x=(w-text_w)/2:y=(h-text_h)/2:" \
      "alpha='if(lt(t,0.25),t/0.25," \
      "if(gt(t,5.5),(6-t)/0.5,1))'," \
      "fade=t=in:st=0:d=0.25," \
      "fade=t=out:st=5.5:d=0.5[vout]"
    )

    music_volume = @random.rand(0.20..0.35).round(2)
    whoosh_delay = @random.rand(400..1400)
    impact_delay = @random.rand(3000..4200)

    filters << (
      "[3:a]atrim=duration=#{DURATION}," \
      "asetpts=PTS-STARTPTS,volume=#{music_volume}[music]"
    )

    filters << (
      "[4:a]atrim=duration=1," \
      "asetpts=PTS-STARTPTS,volume=0.65," \
      "adelay=#{whoosh_delay}|#{whoosh_delay}[whoosh]"
    )

    filters << (
      "[5:a]atrim=duration=1.5," \
      "asetpts=PTS-STARTPTS,volume=0.75," \
      "adelay=#{impact_delay}|#{impact_delay}[impact]"
    )

    filters << (
      "[music][whoosh][impact]" \
      "amix=inputs=3:duration=first:normalize=0," \
      "atrim=duration=#{DURATION}[aout]"
    )

    args = [
      ffmpeg, "-y",
      "-filter_complex_threads", "1",
      "-threads", "1",

      "-stream_loop", "-1", "-i", @root.join(sources[0]).to_s,
      "-stream_loop", "-1", "-i", @root.join(sources[1]).to_s,
      "-stream_loop", "-1", "-i", @root.join(sources[2]).to_s,

      "-stream_loop", "-1",
      "-i", @audio_dir.join("cinematic.mp3").to_s,
      "-i", @audio_dir.join("whoosh.mp3").to_s,
      "-i", @audio_dir.join("impact.mp3").to_s,

      "-filter_complex", filters.join(";"),
      "-map", "[vout]",
      "-map", "[aout]",
      "-t", DURATION.to_s,
      "-c:v", "libx264",
      "-threads", "1",
      "-preset", "ultrafast",
      "-crf", "28",
      "-c:a", "aac",
      "-b:a", "96k",
      "-movflags", "+faststart",
      output.to_s
    ]

    _stdout, stderr, status = Open3.capture3(*args)

    unless status.success? && output.file? && output.size.positive?
      FileUtils.rm_f(output)
      raise "FFmpeg trailer generation failed: #{stderr.lines.last(15).join}"
    end

    "/trailers/generated/#{key}.mp4"
  ensure
    FileUtils.rm_rf(work_dir) if defined?(work_dir) && work_dir
  end

  private

  
  
  def selected_sources
    combinations = SOURCES.combination(CLIP_COUNT).to_a

    position = (@seed.abs + @index * 997) % combinations.length
    combination = combinations[position]

    combination.shuffle(random: Random.new(@seed + @index * 997))
  end



  def safe_text(text)
    text.to_s.gsub(/[\r\n]/, " ").strip
  end

  def windows_font_path
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
