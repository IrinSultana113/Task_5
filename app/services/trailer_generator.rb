
require "fileutils"
require "digest"
require "open3"

class TrailerGenerator
  WIDTH = 640
  HEIGHT = 360
  DURATION = 6.0
  FPS = 24

 SOURCES = %w[
  action.mp4
  city_night.mp4
  nature.mp4
  car_chase.mp4
  rain.mp4
  space.mp4
  city_timelapse.mp4
  rainy_city.mp4
  rainy_street.mp4
  police_chase.mp4
  urban_chase.mp4
  night_cars.mp4
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
    source = selected_source

    raise "Missing trailer footage: #{source}" unless @source_dir.join(source).file?

    %w[cinematic.mp3 whoosh.mp3 impact.mp3].each do |file|
      raise "Missing trailer audio: #{file}" unless @audio_dir.join(file).file?
    end

    FileUtils.mkdir_p(@output_dir)

    key = Digest::SHA256.hexdigest(
      "#{@seed}:#{@index}:#{@title}:trailer-v4"
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

    brightness = @random.rand(-0.06..0.04).round(3)
    contrast = @random.rand(1.05..1.20).round(2)
    saturation = @random.rand(0.85..1.25).round(2)
    zoom = @random.rand(1.0..1.12).round(3)
    speed = @random.rand(0.90..1.10).round(2)

    font_size = @random.rand(30..44)
    title_position = @random.rand(0..2)
    title_start = @random.rand(0.0..0.3).round(2)
    fade_in = @random.rand(0.25..0.60).round(2)

    music_volume = @random.rand(0.20..0.35).round(2)
    whoosh_delay = @random.rand(400..1400)
    impact_delay = @random.rand(3000..4200)

    title_y = case title_position
              when 0 then "(h-text_h)/2"
              when 1 then "h*0.70-text_h/2"
              else "h*0.28-text_h/2"
              end

    # Zoompan uses a deterministic frame counter.
    zoom_filter = (
      "zoompan=z='min(zoom+0.0005,#{zoom})':" \
      "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':" \
      "d=1:s=#{WIDTH}x#{HEIGHT}:fps=#{FPS}"
    )

    filters = []

    filters << (
      "[0:v]" \
      "trim=duration=#{DURATION * speed}," \
      "setpts=PTS/#{speed}," \
      "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=increase," \
      "crop=#{WIDTH}:#{HEIGHT}," \
      "fps=#{FPS}," \
      "eq=contrast=#{contrast}:brightness=#{brightness}:saturation=#{saturation}," \
      "#{zoom_filter}," \
      "setsar=1,format=yuv420p," \
      "drawtext=fontfile='#{font_filter}':textfile='#{text_filter_path}':" \
      "fontcolor=white:fontsize=#{font_size}:" \
      "borderw=2:bordercolor=black@0.8:" \
      "shadowcolor=black@0.7:shadowx=2:shadowy=2:" \
      "x=(w-text_w)/2:y=#{title_y}:" \
      "alpha='if(lt(t,#{title_start}),0,if(lt(t,#{title_start + fade_in})," \
      "(t-#{title_start})/#{fade_in},if(gt(t,5.5),(6.0-t)/0.5,1)))'," \
      "fade=t=in:st=0:d=0.25," \
      "fade=t=out:st=5.5:d=0.5[vout]"
    )

    filters << (
      "[1:a]atrim=duration=#{DURATION}," \
      "asetpts=PTS-STARTPTS,volume=#{music_volume}[music]"
    )

    filters << (
      "[2:a]atrim=duration=1," \
      "asetpts=PTS-STARTPTS,volume=0.65," \
      "adelay=#{whoosh_delay}|#{whoosh_delay}[whoosh]"
    )

    filters << (
      "[3:a]atrim=duration=1.5," \
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

      "-stream_loop", "-1",
      "-i", @source_dir.join(source).to_s,

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

  def selected_source
    # Same seed and index always select the same source.
    SOURCES[Random.new(@seed + @index * 997).rand(SOURCES.length)]
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
