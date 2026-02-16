module ApplicationHelper
  def format_bitrate(value)
    bitrate = value.to_i
    return "не определен" unless bitrate.positive?

    kbps = bitrate / 1000.0
    return "#{kbps.round} кбит/с" if kbps < 1000

    "#{(kbps / 1000.0).round(2)} Мбит/с"
  end
end
