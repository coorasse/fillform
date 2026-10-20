# frozen_string_literal: true

module Fillform
  # The changes pdf-forms and pdftk make to the values and the field names on their way into the
  # form, per data format.
  module DataFormat
    module_function

    def apply(format, value)
      case format.to_s
      when "XFdf" then xfdf(value)
      when "FdfHex" then value
      else fdf(value)
      end
    end

    # The name pdftk looks the field up with. In FDF the names are literal strings that pdftk reads in
    # PDFDocEncoding, so a field whose name is not in PDFDocEncoding is not found and not filled.
    def field_name(format, name)
      case format.to_s
      when "XFdf" then name
      when "FdfHex" then PDF::Text.decode(name.b)
      else latin9_as_pdf_doc(name)
      end
    end

    # Fdf, the default of pdf-forms: the values are written in ISO-8859-15 and read back by pdftk in
    # PDFDocEncoding, a line feed is written as an escaped carriage return and a raw carriage return
    # is read as a line feed.
    def fdf(value)
      latin9_as_pdf_doc(value).gsub(/[\r\n]/, "\r" => "\n", "\n" => "\r")
    end

    # XFdf: pdftk's XML parser collapses a run of the same space, tab or line feed into one and reads
    # carriage returns as line feeds.
    def xfdf(value)
      value.gsub(/([ \t\n])\1+/, '\1').gsub(/\r\n?/, "\n")
    end

    def latin9_as_pdf_doc(text)
      latin = text.encode(Encoding::ISO_8859_15, invalid: :replace, undef: :replace, replace: "?")
      latin.b.each_byte.map { |byte| PDF::Text.pdf_doc_char(byte) || "�" }.join
    end
  end
end
