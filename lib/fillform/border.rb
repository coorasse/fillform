# frozen_string_literal: true

module Fillform
  # Background and border of a widget, read and drawn like iText's BaseField#getBorderAppearance.
  class Border
    STYLES = { D: :dashed, B: :beveled, I: :inset, U: :underline }.freeze

    attr_reader :width, :style

    def initialize(widget, box_width, box_height, comb_cells: 0)
      @box_width = box_width
      @box_height = box_height
      @comb_cells = comb_cells
      characteristics = widget.resolve(widget[:MK])
      characteristics = {} unless characteristics.is_a?(Hash)
      @color = Color.from(characteristics[:BC])
      @background = Color.from(characteristics[:BG])
      @width = @color ? 1 : 0
      @style = :solid
      read_style(widget)
    end

    # The width the text keeps from the box: beveled and inset borders draw a second frame.
    def inner_width = %i[beveled inset].include?(style) ? width * 2 : width

    def appearance
      operations = []
      operations << "#{@background.fill} 0 0 #{n(@box_width)} #{n(@box_height)} re f" if @background
      operations.concat(border)
      operations.empty? ? "" : "q #{operations.join(" ")} Q "
    end

    private

    # iText reads the legacy /Border array only when there is no border style dictionary.
    def read_style(widget)
      if (style = widget.resolve(widget[:BS])).is_a?(Hash)
        @width = style[:W] if style.key?(:W)
        @style = STYLES.fetch(style[:S], :solid)
      elsif widget.key?(:Border) && (border = widget.resolve(widget[:Border])).is_a?(Array) && border.length >= 3
        @width = border[2]
        @style = :dashed if border.length >= 4
      end
    end

    def border
      case style
      when :underline then stroked? ? [stroke_setup, underline] : []
      when :beveled then frame + ["1 g", top_frame, (@background || Color.white).darker.fill, bottom_frame]
      when :inset then frame + ["0.5 g", top_frame, "0.75 g", bottom_frame]
      else frame(dashed: style == :dashed) + comb_dividers
      end
    end

    def comb_dividers
      return [] unless stroked? && @comb_cells > 1

      step = @box_width / @comb_cells
      bottom = n(width / 2.0)
      top = n(@box_height - (width / 2.0))
      lines = (1...@comb_cells).map { |cell| "#{n(step * cell)} #{bottom} m #{n(step * cell)} #{top} l" }
      ["#{lines.join(" ")} S"]
    end

    def stroked? = width.positive? && @color

    def underline = "0 #{n(width / 2.0)} m #{n(@box_width)} #{n(width / 2.0)} l S"

    def stroke_setup = "#{@color.stroke} #{n(width)} w"

    def frame(dashed: false)
      return [] unless stroked?

      inset = width / 2.0
      ["#{"[3] 0 d " if dashed}#{stroke_setup}",
       "#{n(inset)} #{n(inset)} #{n(@box_width - width)} #{n(@box_height - width)} re S"]
    end

    def top_frame
      path([[width, width], [width, @box_height - width], [@box_width - width, @box_height - width],
            [@box_width - (2 * width), @box_height - (2 * width)], [2 * width, @box_height - (2 * width)],
            [2 * width, 2 * width], [width, width]])
    end

    def bottom_frame
      path([[width, width], [@box_width - width, width], [@box_width - width, @box_height - width],
            [@box_width - (2 * width), @box_height - (2 * width)], [@box_width - (2 * width), 2 * width],
            [2 * width, 2 * width], [width, width]])
    end

    def path(points)
      (x, y), *rest = points
      "#{n(x)} #{n(y)} m #{rest.map { |px, py| "#{n(px)} #{n(py)} l" }.join(" ")} f"
    end

    def n(number) = Fillform.number(number)
  end

  # A color of the widget's appearance characteristics, rounded like a java.awt.Color.
  class Color
    def self.from(components)
      components = Array(components).map(&:to_f)
      new(components) unless components.empty?
    end

    def self.white = new([1, 1, 1])

    def initialize(components)
      @components = components.size == 3 ? components.map { |c| (c * 255).round / 255.0 } : components
    end

    def fill = "#{values} #{operator}"

    def stroke = "#{values} #{operator.upcase}"

    # java.awt.Color#darker, always in RGB
    def darker = Color.new(rgb.map { |c| ((c * 255).round * 0.7).floor / 255.0 })

    private

    def rgb
      case @components.size
      when 1 then @components * 3
      when 4
        cyan, magenta, yellow, black = @components
        [cyan, magenta, yellow].map { |c| (1 - c - black).clamp(0.0, 1.0) }
      else @components
      end
    end

    def values = @components.map { |c| Fillform.number(c) }.join(" ")

    def operator = { 1 => "g", 3 => "rg", 4 => "k" }.fetch(@components.size)
  end
end
