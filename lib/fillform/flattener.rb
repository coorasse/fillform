# frozen_string_literal: true

module Fillform
  # Draws the appearances of the fields into their pages and removes the fields, like iText's
  # PdfStamperImp#flatFields: in the order of the field names, each appearance moved to the lower left
  # corner of its widget, only for widgets that are printed and not hidden.
  class Flattener
    HIDDEN = 1 << 1
    PRINT = 1 << 2

    def initialize(document, form)
      @document = document
      @form = form
    end

    def flatten
      pages = @document.pages
      page_of = page_index(pages)
      drawings = Hash.new { |hash, key| hash[key] = [] }
      removed = {}
      @form.fields.sort_by(&:name).each do |field|
        field.widgets.each do |widget|
          index = widget.reference.is_a?(PDF::Reference) ? page_of[widget.reference.number] : nil
          next unless index

          appearance = appearance(widget) if visible?(widget)
          drawings[index] << [appearance, *widget.rect[0, 2]] if appearance
          removed[widget.reference.number] = true
        end
      end
      pages.each_with_index do |(_reference, page, inherited), index|
        remove_widgets(page, removed)
        draw(page, inherited, drawings[index]) if drawings.key?(index)
      end
      @form.dictionary[:Fields] = []
    end

    private

    def page_index(pages)
      pages.each_with_index.with_object({}) do |((_reference, page, _inherited), index), result|
        Array(@document.deref(page[:Annots])).each do |annotation|
          result[annotation.number] ||= index if annotation.is_a?(PDF::Reference)
        end
      end
    end

    def visible?(widget)
      flags = widget[:F].to_i
      flags.anybits?(PRINT) && !flags.anybits?(HIDDEN)
    end

    # The normal appearance, or the one of the widget's state.
    def appearance(widget)
      appearances = widget[:AP]
      return unless appearances.is_a?(Hash)

      normal = appearances[:N]
      value = @document.deref(normal)
      reference = case value
                  when PDF::Stream then normal.is_a?(PDF::Reference) ? normal : @document.add(value)
                  when Hash then value[widget[:AS]] if widget[:AS]
                  end
      stream = @document.deref(reference) if reference.is_a?(PDF::Reference)
      return unless stream.is_a?(PDF::Stream)

      stream[:Subtype] = :Form
      reference
    end

    def remove_widgets(page, removed)
      annotations = Array(@document.deref(page[:Annots]))
      kept = annotations.reject { |annotation| annotation.is_a?(PDF::Reference) && removed[annotation.number] }
      return if kept.size == annotations.size

      kept.empty? ? page.delete(:Annots) : page[:Annots] = kept
    end

    def draw(page, inherited, drawings)
      xobjects = xobjects(page, inherited)
      operations = drawings.map do |reference, left, bottom|
        name = next_name(xobjects)
        xobjects[name] = reference
        "q 1 0 0 1 #{Fillform.number(left)} #{Fillform.number(bottom)} cm #{PDF::Serializer.name(name)} Do Q\n"
      end
      page[:Contents] = [@document.add(PDF::Stream.new({}, "q\n".b)), *contents(page),
                         @document.add(PDF::Stream.new({}, "\nQ\n#{operations.join}".b))]
    end

    def contents(page)
      contents = page[:Contents]
      value = @document.deref(contents)
      case value
      when Array then value
      when nil then []
      else [contents]
      end
    end

    def xobjects(page, inherited)
      page[:Resources] = @document.deref(inherited[:Resources]).dup || {} unless page.key?(:Resources)
      resources = @document.deref(page[:Resources])
      xobjects = @document.deref(resources[:XObject])
      resources[:XObject] = xobjects = {} unless xobjects.is_a?(Hash)
      xobjects
    end

    def next_name(xobjects)
      index = 0
      index += 1 while xobjects.key?(:"Xi#{index}")
      :"Xi#{index}"
    end
  end
end
