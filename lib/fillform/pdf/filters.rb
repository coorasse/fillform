# frozen_string_literal: true

module Fillform
  module PDF
    # The stream filters a form template needs to be read: Flate with predictors, and the ASCII ones.
    module Filters
      module_function

      def decode(data, filters, parameters)
        filters = [filters].compact unless filters.is_a?(Array)
        parameters = [parameters] unless parameters.is_a?(Array)
        filters.each_with_index.reduce(data) do |result, (filter, index)|
          apply(filter, result, parameters[index].is_a?(Hash) ? parameters[index] : {})
        end
      end

      def apply(filter, data, parameters)
        case filter
        when :FlateDecode, :Fl then predict(inflate(data), parameters)
        when :ASCIIHexDecode, :AHx then hex(data)
        when :ASCII85Decode, :A85 then ascii85(data)
        else raise MalformedError, "unsupported stream filter #{filter}"
        end
      end

      # Tolerates truncated and trailing bytes like PDF readers do.
      def inflate(data)
        inflater = Zlib::Inflate.new
        result = +""
        begin
          result << inflater.inflate(data)
        rescue Zlib::BufError, Zlib::DataError
          nil
        end
        result.b
      ensure
        inflater&.close
      end

      def predict(data, parameters)
        predictor = parameters[:Predictor].to_i
        return data if predictor < 2

        colors = (parameters[:Colors] || 1).to_i
        bits = (parameters[:BitsPerComponent] || 8).to_i
        columns = (parameters[:Columns] || 1).to_i
        pixel = [(colors * bits / 8.0).ceil, 1].max
        row = (columns * colors * bits / 8.0).ceil
        predictor == 2 ? tiff(data, row, pixel) : png(data, row, pixel)
      end

      def png(data, row, pixel)
        previous = Array.new(row, 0)
        result = []
        data.bytes.each_slice(row + 1) do |type, *line|
          line.fill(0, line.size...row)
          line.each_index do |i|
            left = i >= pixel ? line[i - pixel] : 0
            above = previous[i]
            above_left = i >= pixel ? previous[i - pixel] : 0
            line[i] = (line[i] + png_predictor(type, left, above, above_left)) & 0xFF
          end
          result.concat(line)
          previous = line
        end
        result.pack("C*")
      end

      def png_predictor(type, left, above, above_left)
        case type
        when 1 then left
        when 2 then above
        when 3 then (left + above) / 2
        when 4 then paeth(left, above, above_left)
        else 0
        end
      end

      def paeth(left, above, above_left)
        estimate = left + above - above_left
        distances = [left, above, above_left].map { |value| (estimate - value).abs }
        return left if distances[0] <= distances[1] && distances[0] <= distances[2]

        distances[1] <= distances[2] ? above : above_left
      end

      def tiff(data, row, pixel)
        data.bytes.each_slice(row).flat_map do |line|
          line.each_index { |i| line[i] = (line[i] + line[i - pixel]) & 0xFF if i >= pixel }
          line
        end.pack("C*")
      end

      def hex(data)
        digits = data.delete("^0-9A-Fa-f>").split(">").first.to_s
        [digits.length.odd? ? "#{digits}0" : digits].pack("H*")
      end

      def ascii85(data)
        text = data.delete(" \t\r\n\f\0").delete_prefix("<~").split("~>").first.to_s.gsub("z", "!!!!!")
        text.scan(/.{1,5}/).map do |group|
          value = group.ljust(5, "u").bytes.reduce(0) { |sum, byte| (sum * 85) + byte - 33 }
          [value].pack("N")[0, group.length - 1]
        end.join.b
      end
    end
  end
end
