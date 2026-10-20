# frozen_string_literal: true

module Fillform
  # Glyph names, the metrics of the 14 standard fonts, and the simple font encodings.
  # The data files are Adobe's: the core 14 AFM files and the Adobe Glyph List, see data/.
  module Glyphs
    DATA = File.expand_path("../../data", __dir__)
    STANDARD_FONTS = %w[Courier Courier-Bold Courier-BoldOblique Courier-Oblique Helvetica Helvetica-Bold
                        Helvetica-BoldOblique Helvetica-Oblique Symbol Times-Bold Times-BoldItalic Times-Italic
                        Times-Roman ZapfDingbats].freeze

    Metrics = Struct.new(:widths, :encoding, :bounding_box, :ascender, :descender)

    class << self
      def standard_font?(name) = STANDARD_FONTS.include?(name.to_s)

      def metrics(font_name)
        @metrics ||= {}
        @metrics[font_name.to_s] ||= read_afm(File.join(DATA, "afm", "#{font_name}.afm"))
      end

      def unicode(name, dingbats: false)
        name = name.to_s
        (dingbats && zapf_dingbats[name]) || glyph_list[name] || algorithmic(name)
      end

      # Glyph names by code of the encodings a font can name.
      def encoding(name)
        @encodings ||= {}
        @encodings[name] ||=
          case name
          when :StandardEncoding then metrics("Helvetica").encoding
          when :WinAnsiEncoding then charset_encoding(Encoding::Windows_1252, 0xA0 => :space, 0xAD => :hyphen)
          when :MacRomanEncoding then charset_encoding(Encoding::MacRoman, 0xCA => :space)
          end
      end

      private

      def read_afm(path)
        widths = {}
        encoding = Array.new(256)
        values = {}
        File.foreach(path, encoding: Encoding::ISO_8859_1) do |line|
          if line.start_with?("C ")
            code = line[/\AC (-?\d+)/, 1].to_i
            name = line[/; N (\S+)/, 1].to_sym
            widths[name] = line[/WX (\S+)/, 1].to_f
            encoding[code] = name if code.between?(0, 255)
          elsif (match = line.match(/\A(FontBBox|Ascender|Descender) (.+)/))
            values[match[1]] = match[2].split.map(&:to_f)
          end
        end
        box = values["FontBBox"]
        Metrics.new(widths, encoding, box, values.dig("Ascender", 0) || box[3], values.dig("Descender", 0) || box[1])
      end

      def charset_encoding(charset, overrides)
        names = metrics("Helvetica").widths.keys.to_h { |name| [unicode(name), name] }
        Array.new(256) do |code|
          overrides.fetch(code) do
            names[code.chr.force_encoding(charset).encode(Encoding::UTF_8)]
          rescue EncodingError
            nil
          end
        end
      end

      def glyph_list
        @glyph_list ||= read_list("glyphlist.txt")
      end

      def zapf_dingbats
        @zapf_dingbats ||= read_list("zapfdingbats.txt")
      end

      def read_list(file)
        File.foreach(File.join(DATA, "agl", file)).each_with_object({}) do |line, list|
          next if line.start_with?("#")

          name, codes = line.chomp.split(";")
          list[name] = codes.split.map(&:hex).pack("U*") if codes
        end
      end

      # uniXXXX and uXXXX[XX] names, and names with a suffix like a.sc.
      def algorithmic(name)
        base = name.split(".").first.to_s
        if (hex = base[/\Auni((?:\h{4})+)\z/, 1])
          hex.scan(/\h{4}/).map(&:hex).pack("U*")
        elsif (hex = base[/\Au(\h{4,6})\z/, 1])
          [hex.hex].pack("U")
        elsif base != name
          glyph_list[base]
        end
      end
    end
  end
end
