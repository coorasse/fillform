# frozen_string_literal: true

module Fillform
  module PDF
    # Writes PDF objects as bytes.
    module Serializer
      NAME_ESCAPE = %r{[^!-~]|[#()<>\[\]{}/%]}n

      module_function

      def serialize(value)
        case value
        when nil then "null"
        when true then "true"
        when false then "false"
        when Integer, Reference then value.to_s
        when Float then number(value)
        when Symbol then name(value)
        when String then string(value)
        when Array then "[#{value.map { |item| serialize(item) }.join(" ")}]"
        when Hash then dictionary(value)
        else raise ArgumentError, "cannot serialize #{value.class}"
        end
      end

      def number(value)
        return "0" unless value.finite?

        text = value.to_s
        text = format("%.12f", value).sub(/\.?0+\z/, "") if text.include?("e")
        text == "-0" ? "0" : text
      end

      def name(value)
        "/#{value.to_s.b.gsub(NAME_ESCAPE) { |char| format("#%02X", char.ord) }}"
      end

      def string(value)
        "(#{value.b.gsub(/[()\\\r]/n) { |char| char == "\r" ? "\\r" : "\\#{char}" }})"
      end

      def dictionary(value)
        "<<#{value.map { |key, item| "#{name(key)} #{serialize(item)}" }.join(" ")}>>"
      end
    end
  end
end
