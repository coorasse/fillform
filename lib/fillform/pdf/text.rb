# frozen_string_literal: true

module Fillform
  module PDF
    # Text strings: PDFDocEncoding, or UTF-16BE (and UTF-8 since PDF 2.0) with a byte order mark.
    module Text
      # The bytes where PDFDocEncoding differs from ISO-8859-1 (PDF 32000-1, annex D.2).
      PDF_DOC_DIFFERENCES = {
        0x18 => 0x02D8, 0x19 => 0x02C7, 0x1A => 0x02C6, 0x1B => 0x02D9, 0x1C => 0x02DD, 0x1D => 0x02DB,
        0x1E => 0x02DA, 0x1F => 0x02DC, 0x7F => nil, 0x80 => 0x2022, 0x81 => 0x2020, 0x82 => 0x2021,
        0x83 => 0x2026, 0x84 => 0x2014, 0x85 => 0x2013, 0x86 => 0x0192, 0x87 => 0x2044, 0x88 => 0x2039,
        0x89 => 0x203A, 0x8A => 0x2212, 0x8B => 0x2030, 0x8C => 0x201E, 0x8D => 0x201C, 0x8E => 0x201D,
        0x8F => 0x2018, 0x90 => 0x2019, 0x91 => 0x201A, 0x92 => 0x2122, 0x93 => 0xFB01, 0x94 => 0xFB02,
        0x95 => 0x0141, 0x96 => 0x0152, 0x97 => 0x0160, 0x98 => 0x0178, 0x99 => 0x017D, 0x9A => 0x0131,
        0x9B => 0x0142, 0x9C => 0x0153, 0x9D => 0x0161, 0x9E => 0x017E, 0x9F => nil, 0xA0 => 0x20AC, 0xAD => nil
      }.freeze
      PDF_DOC = Array.new(256) { |byte| PDF_DOC_DIFFERENCES.fetch(byte, byte)&.chr(Encoding::UTF_8) }.freeze
      PDF_DOC_BYTES = PDF_DOC.each_with_index.filter_map { |char, byte| [char, byte.chr] if char }.to_h.freeze

      module_function

      def decode(bytes)
        bytes = bytes.b
        if bytes.start_with?("\xFE\xFF".b)
          bytes.byteslice(2..).force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8, invalid: :replace)
        elsif bytes.start_with?("\xEF\xBB\xBF".b)
          bytes.byteslice(3..).force_encoding(Encoding::UTF_8).scrub
        else
          bytes.each_byte.map { |byte| PDF_DOC[byte] || "�" }.join
        end
      end

      def pdf_doc_char(byte) = PDF_DOC[byte]

      def encode(text)
        text = text.to_s.encode(Encoding::UTF_8)
        if text.each_char.all? { PDF_DOC_BYTES.key?(_1) }
          return text.each_char.map do |char|
            PDF_DOC_BYTES[char]
          end.join.b
        end

        "\xFE\xFF".b + text.encode(Encoding::UTF_16BE).b
      end
    end
  end
end
