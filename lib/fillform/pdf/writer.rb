# frozen_string_literal: true

module Fillform
  module PDF
    # Writes the given objects of a document as a single revision with a cross-reference table.
    class Writer
      def initialize(document, numbers)
        @document = document
        @numbers = numbers
      end

      def to_pdf
        out = "%PDF-#{version}\n%\xE2\xE3\xCF\xD3\n".b
        offsets = {}
        @numbers.each do |number|
          offsets[number] = out.bytesize
          out << "#{number} 0 obj\n".b << body(@document.object(number)) << "\nendobj\n".b
        end
        size = (@numbers.max || 0) + 1
        xref = out.bytesize
        out << cross_references(offsets, size)
        out << "trailer\n#{Serializer.serialize(trailer(size))}\nstartxref\n#{xref}\n%%EOF\n".b
      end

      private

      def version
        catalog_version = @document.catalog[:Version].to_s
        [catalog_version, @document.version].max
      end

      def body(value)
        return Serializer.serialize(value).b unless value.is_a?(Stream)

        dictionary = value.dictionary.merge(Length: value.raw.bytesize)
        "#{Serializer.serialize(dictionary)}\nstream\n".b << value.raw.b << "\nendstream".b
      end

      def cross_references(offsets, size)
        lines = Array.new(size) do |number|
          offsets.key?(number) ? format("%010d 00000 n \n", offsets[number]) : "0000000000 65535 f \n"
        end
        "xref\n0 #{size}\n#{lines.join}".b
      end

      def trailer(size)
        @document.trailer.slice(:Root, :Info, :ID).merge(Size: size)
      end
    end
  end
end
