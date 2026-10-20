# frozen_string_literal: true

module Fillform
  class Filler
    def initialize(template)
      @doc = PDF::Document.open(template.to_s)
      @form = Form.new(@doc)
    end

    def fill(data, flatten: false)
      return self unless @form.present?

      fields = @form.fields.to_h { |field| [field.name, field] }
      data.each do |name, value|
        field = fields[name.to_s]
        next unless field

        case field.concrete_type
        when :check_box, :radio_button then select_state(field, value.to_s)
        when :text_field then appearance(field).fill(value.to_s)
        when :combo_box then appearance(field).fill_choice(value.to_s)
        when :list_box then appearance(field).fill_list(Array(value).map(&:to_s))
        end
      end
      Flattener.new(@doc, @form).flatten if flatten
      self
    end

    # Not validated: like pdftk, a value longer than the field's MaxLen is kept as it is.
    def write(destination)
      @doc.write(destination.to_s)
    end

    private

    # Like pdftk, an unknown state leaves the button as it is, and the template's own appearance of
    # the state is drawn.
    def select_state(field, value)
      state = value == "Off" ? :Off : on_states(field).find { |name| state_name?(name, value) }
      return unless state

      field[:V] = state
      field.widgets.each do |widget|
        appearances = widget.normal_appearances
        widget[:AS] = appearances.is_a?(Hash) && appearances.key?(state) ? state : :Off
      end
    end

    def on_states(field)
      field.widgets.flat_map do |widget|
        appearances = widget.normal_appearances
        appearances.is_a?(Hash) ? appearances.keys : []
      end.uniq - [:Off]
    end

    # pdftk shows and matches the bytes of a state name as Latin-1, so its users pass "SÃ¬" for "Sì".
    def state_name?(name, value)
      bytes = name.to_s.b
      utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
      (utf8.valid_encoding? && utf8 == value) || Field.latin1(name) == value
    end

    def appearance(field)
      Appearance.new(@doc, field, form: @form) { |resources, name| font(resources, name) }
    end

    # iText draws with Helvetica when the font of the field is not in its resources.
    def font(resources, name)
      @fonts ||= {}
      @fonts[[resources.object_id, name]] ||= begin
        fonts = @doc.deref(resources[:Font]) if resources.is_a?(Hash)
        resource = fonts[name.to_sym] if fonts.is_a?(Hash) && name
        @doc.deref(resource).is_a?(Hash) ? Font.new(name.to_sym, resource, @doc) : helvetica
      end
    end

    def helvetica
      @helvetica ||= Font.new(:Helv, @doc.add({ Type: :Font, Subtype: :Type1, BaseFont: :Helvetica,
                                                Encoding: :WinAnsiEncoding }), @doc, fallback: true)
    end
  end
end
