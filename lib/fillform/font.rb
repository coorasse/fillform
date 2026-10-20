# frozen_string_literal: true

module Fillform
  # The metrics and the encoding iText reads from a font of the form's resources.
  class Font
    # iText encodes with the Java charsets of these encodings; any other encoding goes by glyph names.
    CHARSETS = { WinAnsiEncoding: Encoding::Windows_1252, MacRomanEncoding: Encoding::MacRoman }.freeze

    attr_reader :key, :resource

    # iText's own fallback font drops the characters it cannot show, a font of the form shows code 0.
    # The resource is what the appearance stream lists for the font: a reference or a dictionary.
    def initialize(key, resource, document, fallback: false)
      @key = key
      @resource = resource
      @document = document
      @dictionary = document.deref(resource)
      @missing = fallback ? nil : 0
    end

    def encode(char)
      @codes ||= {}
      return @codes[char] if @codes.key?(char)

      @codes[char] = differences[char] || charset_code(char) || (charset ? nil : base_codes[char]) || @missing
    end

    def encode_all(chars) = chars.filter_map { |char| encode(char) }

    # iText's BaseFont#getWidthPoint with the integer width of the glyph.
    def char_width(char, size)
      code = encode(char)
      f(f(f(code ? width(code).to_i : 0) * Float32::THOUSANDTH) * f(size))
    end

    # iText's quirk: the height of a line is measured from the lower left to the upper right corner.
    def auto_size_factor = f(metric(bounding_box[2], 1) - metric(bounding_box[1], 1))

    def line_factor = f(metric(bounding_box[3], 1) - metric(bounding_box[1], 1))

    def top(size) = metric(bounding_box[3], size)

    def bottom(size) = metric(bounding_box[1], size)

    def ascent(size) = metric(metrics[1], size)

    def descent(size) = metric(metrics[2], size)

    private

    # iText's BaseFont#getFontDescriptor: value * size / 1000 in floats.
    def metric(value, size) = f(f(f(value) * f(size)) / 1000)

    def f(value) = Float32.f(value)

    def width(code)
      @widths ||= {}
      @widths[code] ||=
        if (widths = deref(@dictionary[:Widths]))
          first = @dictionary[:FirstChar].to_i
          code.between?(first, first + widths.size - 1) ? deref(widths[code - first]).to_f : missing_width
        elsif standard_font?
          standard_metrics.widths[names[code]] || 0
        else
          missing_width
        end
    end

    def missing_width = deref(descriptor&.[](:MissingWidth)).to_f

    def encoding = deref(@dictionary[:Encoding])

    def base_encoding_name
      encoding.is_a?(Hash) ? encoding[:BaseEncoding] : encoding
    end

    def charset
      return @charset if defined?(@charset)

      @charset = CHARSETS[base_encoding_name]
    end

    # Where Ruby's MacRoman table differs from Java's.
    JAVA_MAC_ROMAN = { "¤" => nil, "Ω" => 0xBD, "€" => 0xDB, "Ω" => nil, "" => 0xF0 }.freeze

    def charset_code(char)
      return unless charset
      return JAVA_MAC_ROMAN[char] if charset == Encoding::MacRoman && JAVA_MAC_ROMAN.key?(char)

      char.encode(charset).ord
    rescue EncodingError
      nil
    end

    # Glyph names by code: the base encoding with the differences of the font applied.
    def names
      @names ||= base_names.dup.tap do |result|
        difference_names.each { |code, name| result[code] = name }
      end
    end

    def base_names
      Glyphs.encoding(base_encoding_name) || builtin_names
    end

    def builtin_names
      standard_font? ? standard_metrics.encoding : Glyphs.encoding(:StandardEncoding)
    end

    def difference_names
      @difference_names ||= begin
        code = 0
        Array(deref(encoding.is_a?(Hash) ? encoding[:Differences] : nil)).each_with_object({}) do |item, result|
          item = deref(item)
          if item.is_a?(Numeric)
            code = item.to_i
          else
            result[code] = item
            code += 1
          end
        end
      end
    end

    def differences
      @differences ||= unicode_codes(difference_names)
    end

    def base_codes
      @base_codes ||= unicode_codes(base_names.each_with_index.to_h { |name, code| [code, name] })
    end

    def unicode_codes(names_by_code)
      dingbats = @dictionary[:BaseFont].to_s == "ZapfDingbats"
      names_by_code.each_with_object({}) do |(code, name), result|
        next unless name

        char = Glyphs.unicode(name, dingbats: dingbats)
        result[char] = code if char && !result.key?(char)
      end
    end

    def bounding_box = metrics[0]

    def metrics
      @metrics ||=
        if standard_font?
          [standard_metrics.bounding_box, standard_metrics.ascender, standard_metrics.descender]
        else
          [deref(descriptor[:FontBBox]).map { |value| deref(value).to_f }, deref(descriptor[:Ascent]).to_f,
           deref(descriptor[:Descent]).to_f]
        end
    end

    def descriptor = deref(@dictionary[:FontDescriptor])

    def standard_metrics = Glyphs.metrics(@dictionary[:BaseFont])

    def standard_font?
      @dictionary[:Subtype] == :Type1 && Glyphs.standard_font?(@dictionary[:BaseFont])
    end

    def deref(value) = @document.deref(value)
  end
end
