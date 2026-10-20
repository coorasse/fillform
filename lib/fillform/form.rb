# frozen_string_literal: true

module Fillform
  # The interactive form of a document: its terminal fields, in the order of the field tree.
  class Form
    attr_reader :document, :dictionary

    def initialize(document)
      @document = document
      @dictionary = document.deref(document.catalog&.[](:AcroForm))
    end

    def present? = @dictionary.is_a?(Hash)

    def [](key) = present? ? @document.deref(@dictionary[key]) : nil

    def fields
      return [] unless present?

      @fields ||= Array(self[:Fields]).flat_map { |reference| terminal_fields(reference, nil, 0) }
    end

    def field(name) = fields.find { |field| field.name == name }

    private

    def terminal_fields(reference, parent, depth)
      dictionary = @document.deref(reference)
      return [] unless dictionary.is_a?(Hash) && depth < 32

      field = FormField.new(@document, reference, dictionary, parent)
      kids = field.field_kids
      kids.empty? ? [field] : kids.flat_map { |kid| terminal_fields(kid, field, depth + 1) }
    end
  end

  # A field of the form, with the attributes it inherits from its parents.
  class FormField
    INHERITABLE = %i[FT Ff V DV DA Q MaxLen].freeze
    PUSH_BUTTON = 1 << 16
    RADIO = 1 << 15
    COMBO = 1 << 17

    attr_reader :document, :reference, :dictionary, :parent

    def initialize(document, reference, dictionary, parent)
      @document = document
      @reference = reference
      @dictionary = dictionary
      @parent = parent
    end

    def [](key)
      value = @document.deref(@dictionary[key])
      return value unless value.nil? && INHERITABLE.include?(key) && @parent

      @parent[key]
    end

    def []=(key, value)
      @dictionary[key] = value
    end

    def key?(key) = @dictionary.key?(key)

    # A value of the field or of the nearest parent that has it.
    def lookup(key)
      @dictionary.key?(key) ? @document.deref(@dictionary[key]) : @parent&.lookup(key)
    end

    def name
      own = @dictionary[:T] && PDF::Text.decode(@document.deref(@dictionary[:T]))
      [@parent&.name, own].compact.join(".")
    end

    def field_type = self[:FT]

    def flags = self[:Ff].to_i

    def concrete_type
      case field_type
      when :Btn then button_type
      when :Ch then flags.nobits?(COMBO) ? :list_box : :combo_box
      when :Tx then :text_field
      else field_type
      end
    end

    # Kids with a name are fields, the other kids are widgets.
    def field_kids
      kids.select { |kid| @document.deref(kid).is_a?(Hash) && @document.deref(kid).key?(:T) }
    end

    # The field itself when its widget is merged into it.
    def widgets
      widget_kids = kids.reject { |kid| @document.deref(kid).is_a?(Hash) && @document.deref(kid).key?(:T) }
      references = kids.empty? ? [@reference] : widget_kids
      references.filter_map do |reference|
        dictionary = @document.deref(reference)
        Widget.new(@document, reference, dictionary) if dictionary.is_a?(Hash)
      end
    end

    private

    def kids = Array(@document.deref(@dictionary[:Kids]))

    def button_type
      return :push_button if flags.anybits?(PUSH_BUTTON)

      flags.nobits?(RADIO) ? :check_box : :radio_button
    end
  end

  # A widget annotation of a field.
  class Widget
    attr_reader :reference, :dictionary

    def initialize(document, reference, dictionary)
      @document = document
      @reference = reference
      @dictionary = dictionary
    end

    def [](key) = @document.deref(@dictionary[key])

    # A value of the widget's entries, with any reference inside it resolved.
    def resolve(value)
      value = @document.deref(value)
      case value
      when Array then value.map { |item| resolve(item) }
      when Hash then value.transform_values { |item| resolve(item) }
      else value
      end
    end

    def []=(key, value)
      @dictionary[key] = value
    end

    def key?(key) = @dictionary.key?(key)

    # The normalized rectangle: [left, bottom, right, top].
    def rect
      left, bottom, right, top = Array(self[:Rect]).map { |value| @document.deref(value).to_f }
      [[left, right].min, [bottom, top].min, [left, right].max, [bottom, top].max]
    end

    def normal_appearances
      appearances = self[:AP]
      appearances.is_a?(Hash) ? @document.deref(appearances[:N]) : nil
    end

    # The names of the states the widget has a normal, down and rollover appearance for.
    def states_by_kind
      appearances = self[:AP]
      return [] unless appearances.is_a?(Hash)

      %i[N D R].map do |key|
        states = @document.deref(appearances[key])
        states.is_a?(Hash) ? states.keys : []
      end
    end
  end
end
