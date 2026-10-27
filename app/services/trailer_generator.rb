
require "fileutils"
require "digest"
require "open3"

class TrailerGenerator
  WIDTH = 1280
  HEIGHT = 720
  DURATION = 7.5
  CLIP_DURATION = 2.5
  FPS = 30

  def initialize(seed:, index:, title:)
    @seed = Integer(seed)
    @index = Integer(index)
    @title = title.to_s
    @random = Random.new(@seed + @index * 997)
    raise ArgumentError, "Index must be non-negative" if @index.negative?
    @root = Rails.root
    @source_dir = @root.join("public/trailers")
    @audio_dir = @source_dir.join("audio")
    @output_dir = @source_dir.join("generated")
  end

  def call
    sources = ordered_sources
    audio_files = %w[cinematic.mp3 whoosh.mp3 impact.mp3]

    sources.each do |file|
      raise "Missing trailer footage: #{file}" unless @source_dir.join(file).file?
    end

    audio_files.each do |file|
      raise "Missing trailer audio: #{file}" unless @audio_dir.join(file).file?
    end

    FileUtils.mkdir_p(@output_dir)

    key = Digest::SHA256.hexdigest(
      "#{@seed}:#{@index}:#{@title}"
    )[0, 24]

    output = @output_dir.join("#{key}.mp4")

    if output.file? && output.size.positive?
      return "/trailers/generated/#{key}.mp4"
    end

    ffmpeg = ENV.fetch("FFMPEG_PATH", "ffmpeg")
    font = windows_font_path

    music = @audio_dir.join("cinematic.mp3")
    whoosh = @audio_dir.join("whoosh.mp3")
    impact = @audio_dir.join("impact.mp3")

    work_dir = @root.join("tmp/trailer_work", key)
    FileUtils.mkdir_p(work_dir)

    text_path = work_dir.join("title.txt")
    File.write(text_path, safe_text(@title), encoding: "UTF-8")

    text_filter_path = text_path.to_s.tr("\\", "/").gsub(":", "\\:")
    font_filter = font.tr("\\", "/").gsub(":", "\\:")

    brightness = @random.rand(-0.04..0.02).round(3)
    contrast = @random.rand(1.05..1.18).round(2)

    filters = []

    # Prepare each video clip with consistent dimensions and timing.
    3.times do |i|
      filters << (
        "[#{i}:v]" \
        "trim=duration=#{CLIP_DURATION}," \
        "setpts=PTS-STARTPTS," \
        "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=increase," \
        "crop=#{WIDTH}:#{HEIGHT}," \
        "fps=#{FPS}," \
        "eq=contrast=#{contrast}:brightness=#{brightness}:saturation=1.12," \
        "setsar=1,format=yuv420p[v#{i}]"
      )
    end

    # Join all three clips into one video stream.
    filters << (
      "[v0][v1][v2]" \
      "concat=n=3:v=1:a=0[joined]"
    )

    # Add the movie title over the complete trailer.
    filters << (
      "[joined]" \
      "drawtext=fontfile='#{font_filter}':textfile='#{text_filter_path}':" \
      "fontcolor=white:fontsize=64:" \
      "borderw=2:bordercolor=black@0.8:" \
      "shadowcolor=black@0.7:shadowx=3:shadowy=3:" \
      "x=(w-text_w)/2:y=(h-text_h)/2:" \
      "alpha='if(lt(t,0.35),t/0.35,if(gt(t,7.15),(7.5-t)/0.35,1))'," \
      "format=yuv420p[vout]"
    )

    # Background music.
    filters << (
      "[3:a]atrim=duration=#{DURATION}," \
      "asetpts=PTS-STARTPTS,volume=0.30[music]"
    )

    # Sound effects.
    filters << (
      "[4:a]atrim=duration=1," \
      "asetpts=PTS-STARTPTS,volume=0.75," \
      "adelay=700|700[whoosh]"
    )

    filters << (
      "[5:a]atrim=duration=1.5," \
      "asetpts=PTS-STARTPTS,volume=0.9," \
      "adelay=4200|4200[impact]"
    )

    filters << (
      "[music][whoosh][impact]" \
      "amix=inputs=3:duration=first:normalize=0[aout]"
    )

    args = [
      ffmpeg, "-y",

      # Three source videos, each looped if needed.
      "-stream_loop", "-1", "-i", @source_dir.join(sources[0]).to_s,
      "-stream_loop", "-1", "-i", @source_dir.join(sources[1]).to_s,
      "-stream_loop", "-1", "-i", @source_dir.join(sources[2]).to_s,

      # Audio inputs.
      "-stream_loop", "-1", "-i", music.to_s,
      "-i", whoosh.to_s,
      "-i", impact.to_s,

      "-filter_complex", filters.join(";"),
      "-map", "[vout]",
      "-map", "[aout]",
      "-t", DURATION.to_s,
      "-c:v", "libx264",
      "-preset", "veryfast",
      "-crf", "23",
      "-c:a", "aac",
      "-b:a", "160k",
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

  def ordered_sources
    sources = %w[action.mp4 city_night.mp4 nature.mp4]
    orders = sources.permutation.to_a
    orders.shuffle(random: Random.new(@seed))[@index % orders.length]
  end
  private

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

