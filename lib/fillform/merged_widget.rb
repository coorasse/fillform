# frozen_string_literal: true

module Fillform
  # A widget with the attributes of its field and the field's parents, like iText's merged
  # dictionary: the widget's own entries win.
  class MergedWidget
    def initialize(widget, field)
      @widget = widget
      @field = field
    end

    def [](key) = @widget.key?(key) ? @widget[key] : @field.lookup(key)

    def key?(key) = @widget.key?(key) || !@field.lookup(key).nil?

    def resolve(value) = @widget.resolve(value)

    def rect = @widget.rect
  end
end
