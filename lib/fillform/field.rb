# frozen_string_literal: true

module Fillform
  # The metadata of a form field, with the attributes and string values pdf-forms reads from
  # `pdftk dump_data_fields`. See Report for how pdftk walks the field tree.
  Field = Struct.new(:name, :type, :options, :flags, :justification, :value, :value_default, :name_alt,
                     :max_length, keyword_init: true)

  class Field
    # pdftk reads the bytes of a name as Latin-1.
    def self.latin1(name) = name.to_s.b.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)

    def to_hash = to_h
  end
end
