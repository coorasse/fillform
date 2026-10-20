# frozen_string_literal: true

module Fillform
  # The field report of `pdftk dump_data_fields`, as pdf-forms parses it: pdftk's ReportAcroFormFields,
  # which walks the field tree with an accumulated state and reports a node when its kids are unnamed.
  class Report
    State = Struct.new(:type, :name, :name_alt, :flags, :field_values, :default, :justification, :max_length,
                       :option_list, :states, :pairs) do
      def self.empty = new("", "", "", 0, [], "", 0, 0, false, [], [])

      def copy = State.new(*to_a.map { |value| value.is_a?(Array) ? value.dup : value })
    end

    TYPES = { Btn: "Button", Tx: "Text", Ch: "Choice", Sig: "Signature" }.freeze
    JUSTIFICATIONS = %w[Left Center Right].freeze

    def initialize(document)
      @document = document
    end

    def fields
      @fields = []
      form = @document.deref(@document.catalog&.[](:AcroForm))
      kids = @document.deref(form[:Fields]) if form.is_a?(Hash)
      walk(kids, State.empty, 0) if kids.is_a?(Array)
      @fields
    end

    private

    # Returns whether any kid has a name.
    def walk(kids, state, depth)
      saved = state.copy
      named = false
      kids.each do |kid|
        node = @document.deref(kid)
        next unless node.is_a?(Hash)
        next unless read?(node, state)

        if (children = @document.deref(node[:Kids])).is_a?(Array) && depth < 32
          children_named = walk(children, state, depth + 1)
          output(state) if !children_named && name?(node)
          restore(state, saved)
          named ||= children_named
        elsif name?(node)
          output(state)
          restore(state, saved)
          named = true
        end
      end
      named
    end

    # Reads the attributes of a node into the state; false when its value is a null object.
    def read?(node, state)
      type = value(node, :FT)
      state.type = TYPES.fetch(type, state.type) if type.is_a?(Symbol)
      title = value(node, :T)
      if title.is_a?(String)
        state.name = [state.name.empty? ? nil : state.name,
                      PDF::Text.decode(title)].compact.join(".")
      end
      alternate = value(node, :TU)
      state.name_alt = alternate.is_a?(String) ? PDF::Text.decode(alternate) : ""
      state.flags = value(node, :Ff).to_i if value(node, :Ff).is_a?(Numeric)
      return false unless read_value?(node, state)

      read_attributes(node, state)
      true
    end

    def read_value?(node, state)
      return true unless node.key?(:V)

      value = value(node, :V)
      return false if value.nil?

      Array(value.is_a?(Array) ? value : [value]).each do |item|
        text = text_or_name(@document.deref(item))
        state.field_values |= [text] if text
      end
      true
    end

    def read_attributes(node, state)
      default = text_or_name(value(node, :DV))
      state.default = default if default
      state.justification = value(node, :Q).to_i if value(node, :Q).is_a?(Numeric)
      state.max_length = value(node, :MaxLen).to_i if value(node, :MaxLen).is_a?(Numeric)
      read_options(value(node, :Opt), state) if value(node, :Opt).is_a?(Array)
      appearances = value(node, :AP)
      %i[N D R].each { |kind| read_states(@document.deref(appearances[kind]), state) } if appearances.is_a?(Hash)
    end

    def read_options(options, state)
      state.option_list = true
      options.each do |option|
        option = @document.deref(option)
        if option.is_a?(String)
          state.states |= [PDF::Text.decode(option)]
        elsif option.is_a?(Array)
          texts = option.map { |item| @document.deref(item) }.grep(String)
          state.pairs |= [texts.map { |text| PDF::Text.decode(text) }] if texts.size == 2
        end
      end
    end

    # pdftk lists the states of an appearance dictionary in the iteration order of a java.util.HashMap,
    # and only the Off state when the field has an option list.
    def read_states(appearances, state)
      return unless appearances.is_a?(Hash)

      names = JavaHashMap.order(appearances.keys)
      names = names.select { |name| name == :Off } if state.option_list
      state.states |= names.map { |name| Field.latin1(name) }
    end

    def restore(state, saved)
      saved.copy.to_a.each_with_index { |value, index| state[index] = value }
    end

    def name?(node) = value(node, :T).is_a?(String)

    def value(node, key) = @document.deref(node[key])

    def text_or_name(value)
      case value
      when String then PDF::Text.decode(value)
      when Symbol then Field.latin1(value)
      end
    end

    # As pdf-forms reads the lines: the last value wins, leading whitespace and a trailing line end go.
    def output(state)
      @fields << Field.new(
        name: state.name, type: state.type, flags: state.flags.to_s,
        options: lines(state.states + state.pairs.map(&:first)),
        justification: JUSTIFICATIONS.fetch(state.justification, state.justification.to_s),
        value: line(interpret(state, state.field_values.last)),
        value_default: line(state.default.empty? ? nil : interpret(state, state.default)),
        name_alt: line(state.name_alt.empty? ? nil : state.name_alt),
        max_length: (state.max_length.to_s if state.max_length.positive?)
      )
    end

    # pdftk shows the value of a button with an option list as the option its number points to.
    def interpret(state, value)
      return value unless value && state.type == "Button" && state.option_list && value.match?(/\A[+-]?\d{1,9}\z/)

      index = value.to_i
      index.between?(0, state.states.size - 1) ? state.states[index] : value
    end

    def lines(values) = values.empty? ? nil : values.map { |value| value.lstrip.chomp }

    def line(value) = value&.lstrip&.chomp
  end

  # The iteration order of the keys of a java.util.HashMap holding iText PdfNames.
  module JavaHashMap
    ESCAPED = [32, 35, 37, 40, 41, 47, 60, 62, 91, 93, 123, 125].freeze

    module_function

    def order(names)
      capacity = 16
      capacity *= 2 while names.size > capacity * 3 / 4
      names.each_with_index.sort_by { |name, index| [bucket(name, capacity), index] }.map(&:first)
    end

    # The hash of iText's PdfName is computed over the name in iText's encoding, with the slash.
    def bucket(name, capacity)
      encoded = name.to_s.b.each_byte.map do |byte|
        ESCAPED.include?(byte) || !byte.between?(32, 126) ? format("#%02x", byte) : byte.chr
      end
      hash = "/#{encoded.join}".each_byte.reduce(0) { |sum, byte| ((sum * 31) + byte) & 0xFFFFFFFF }
      (hash ^ (hash >> 16)) & (capacity - 1)
    end
  end
end
