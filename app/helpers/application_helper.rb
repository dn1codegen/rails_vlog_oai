module ApplicationHelper
  def format_bitrate(value)
    bitrate = value.to_i
    return "не определен" unless bitrate.positive?

    kbps = bitrate / 1000.0
    return "#{kbps.round} кбит/с" if kbps < 1000

    "#{(kbps / 1000.0).round(2)} Мбит/с"
  end

  def format_file_size(value)
    bytes = value.to_i
    return "не определен" unless bytes.positive?

    units = %w[Б КБ МБ ГБ ТБ].freeze
    size = bytes.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end

    formatted_size = if unit_index.zero?
      size.to_i.to_s
    elsif size >= 10
      size.round(1).to_s.sub(/\.0\z/, "")
    else
      size.round(2).to_s.sub(/\.0+\z/, "").sub(/(\.\d*[1-9])0+\z/, '\1')
    end

    "#{formatted_size} #{units[unit_index]}"
  end
end
