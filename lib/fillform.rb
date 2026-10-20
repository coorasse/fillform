# frozen_string_literal: true

require_relative "fillform/version"

# Fills AcroForm PDF templates in pure Ruby. The appearance of a filled field is built with the
# formulas of pdftk (iText 2.1.7), so the documents look the same as the ones pdftk fills.
module Fillform
  class Error < StandardError; end

  class << self
    def fill(template, destination, data = {}, flatten: false)
      Filler.new(template).fill(data, flatten: flatten).write(destination)
    end

    def fields(template)
      Report.new(PDF::Document.open(template.to_s)).fields
    end

    def field_names(template)
      fields(template).map(&:name)
    end

    # Numbers in content streams are written like iText's ByteBuffer#formatDouble writes a float: five
    # decimals below 1, two up to 32767, none above, each truncated after adding half of the last digit.
    def number(value)
      value = [value].pack("e").unpack1("e")
      return "0" if value.abs < 0.000015

      sign = value.negative? ? "-" : ""
      value = value.abs
      text = if value < 1.0
               fraction(value + 0.000005, 100_000, 5)
             elsif value <= 32_767
               fraction(value + 0.005, 100, 2)
             else
               (value + 0.5).to_i.to_s
             end
      "#{sign}#{text}"
    end

    private

    def fraction(value, scale, digits)
      return "1" if digits == 5 && value >= 1

      scaled = (value * scale).to_i
      whole, decimals = scaled.divmod(scale)
      decimals.zero? ? whole.to_s : "#{whole}.#{decimals.to_s.rjust(digits, "0").sub(/0+\z/, "")}"
    end
  end
end

require_relative "fillform/pdf"
require_relative "fillform/glyphs"
require_relative "fillform/form"
require_relative "fillform/merged_widget"
require_relative "fillform/field"
require_relative "fillform/report"
require_relative "fillform/font"
require_relative "fillform/float32"
require_relative "fillform/line_breaker"
require_relative "fillform/border"
require_relative "fillform/appearance"
require_relative "fillform/flattener"
require_relative "fillform/filler"
