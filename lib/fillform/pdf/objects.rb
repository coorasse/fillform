# frozen_string_literal: true

require "zlib"

module Fillform
  module PDF
    class MalformedError < Fillform::Error; end

    # Dictionaries are Hashes with Symbol keys, names are Symbols, strings are binary Strings.
    Reference = Struct.new(:number, :generation) do
      def to_s = "#{number} #{generation} R"
      alias_method :inspect, :to_s
    end

    class Stream
      attr_accessor :dictionary, :raw

      # A new stream is compressed, a stream read from a file keeps its encoded bytes.
      def self.compressed(dictionary, data)
        new(dictionary.merge(Filter: :FlateDecode), Zlib::Deflate.deflate(data))
      end

      def initialize(dictionary, raw)
        @dictionary = dictionary
        @raw = raw
      end

      def [](key) = @dictionary[key]

      def []=(key, value)
        @dictionary[key] = value
      end

      def key?(key) = @dictionary.key?(key)

      def data(document = nil)
        Filters.decode(@raw, resolve(document, @dictionary[:Filter]), resolve(document, @dictionary[:DecodeParms]))
      end

      private

      def resolve(document, value)
        value = document.deref(value) if document
        value.is_a?(Array) && document ? value.map { |item| document.deref(item) } : value
      end
    end
  end
end
