# frozen_string_literal: true

module Fillform
  # The appearance stream iText's TextField#getAppearance builds: background and border of the widget,
  # then the text with iText's auto font size, baseline, comb cells, alignment and line spacing.
  class Appearance
    COMB = 1 << 24
    MULTILINE = 1 << 12
    MULTILINE_MAX_AUTO_SIZE = 12
    MIN_AUTO_SIZE = 4

    DEFAULT_APPEARANCE = /(\S*)\s+([\d.]+)\s+Tf/
    ROTATIONS = { 90 => [0, 1, -1, 0, :height, 0], 180 => [-1, 0, 0, -1, :width, :height],
                  270 => [0, -1, 1, 0, 0, :width] }.freeze

    # The fonts are looked up with a block: font(resources, name).
    def initialize(doc, field, form:, &fonts)
      @doc = doc
      @field = field
      @form = form
      @fonts = fonts
    end

    def fill(value, shown = value)
      @field[:V] = PDF::Text.encode(value)
      @field.widgets.each { |widget| widget[:AP] = { N: stream_for(widget, shown) } }
    end

    # A combo box shows the text of the option whose export value is the value.
    def fill_choice(value)
      option = Array(@doc.deref(@field[:Opt])).map { |item| @doc.deref(item) }.find do |item|
        item.is_a?(Array) && PDF::Text.decode(@doc.deref(item.first).to_s) == value
      end
      fill(value, option ? PDF::Text.decode(@doc.deref(option.last).to_s) : value)
    end

    # A list box shows the options from the first selected one on, the selected ones highlighted.
    def fill_list(values)
      options = choice_options
      selections = values.filter_map { |value| options.index { |export, _display| export == value } }
      @field[:V] = values.map { |value| PDF::Text.encode(value) }
      @field[:I] = selections
      @field.widgets.each do |widget|
        widget[:AP] = { N: list_stream_for(widget, options.map(&:last), selections) }
      end
    end

    private

    LIST_HIGHLIGHT = Color.new([10, 36, 106].map { |component| component / 255.0 })

    # [export, display] of each option.
    def choice_options
      Array(@doc.deref(@field[:Opt])).map do |option|
        option = @doc.deref(option)
        texts = Array(option).map { |text| PDF::Text.decode(@doc.deref(text).to_s) }
        [texts.first, texts.last]
      end
    end

    def list_stream_for(widget, choices, selections)
      configure(widget)
      @border = Border.new(@widget, @width, @height)
      content = @border.appearance.b
      content << "/Tx BMC ".b << list_text(choices, selections) << "EMC ".b unless choices.empty?
      form_xobject(content)
    end

    def merged(key) = @widget[key]

    # iText reads the attributes of each widget merged with the ones of its field and the form.
    def configure(widget)
      @widget = MergedWidget.new(widget, @field)
      default_appearance = (merged(:DA) || @form[:DA]).to_s.b
      name, size = default_appearance.match(DEFAULT_APPEARANCE)&.captures
      resources = merged(:DR) || @form[:DR]
      @font = @fonts.call(resources, name.to_s.split("/").last)
      @font_size = size.to_f
      @color = default_appearance.sub(DEFAULT_APPEARANCE, "").strip
      @width, @height = box(widget.rect)
      @width, @height = @height, @width if [90, 270].include?(rotation)
    end

    # The rotation of the widget's appearance characteristics, in multiples of 90 degrees.
    def rotation
      characteristics = @widget[:MK]
      degrees = characteristics.is_a?(Hash) ? @doc.deref(characteristics[:R]).to_i : 0
      (degrees % 90).zero? ? degrees % 360 : 0
    end

    def form_xobject(content)
      matrix = ROTATIONS.fetch(rotation, [1, 0, 0, 1, 0, 0]).map do |value|
        { width: @width, height: @height }.fetch(value, value)
      end
      @doc.add(PDF::Stream.compressed({ Type: :XObject, Subtype: :Form,
                                        BBox: [0, 0, @width, @height].map { |number| n(number).to_f },
                                        Matrix: matrix.map { |number| number.is_a?(Float) ? n(number).to_f : number },
                                        Resources: { Font: { @font.key => @font.resource } } }, content))
    end

    # iText's TextField#getListAppearance
    def list_text(choices, selections)
      inset = @border.inner_width
      size = @font_size.zero? ? MULTILINE_MAX_AUTO_SIZE : @font_size
      leading = f(@font.top(size) - @font.bottom(size))
      rows = visible_choices(choices.size, selections, f(inner_height / leading).to_i + 1)
      clip = [inset, inset, f(@width - f(2 * inset)), f(@height - f(2 * inset))].map { |number| n(number) }.join(" ")
      top = f(inset + inner_height)
      "q #{clip} re W n #{LIST_HIGHLIGHT.fill} #{highlights(selections, rows, top, leading)}".b <<
        list_rows(choices, selections, rows, size, top) << "Q ".b
    end

    def visible_choices(count, selections, fitting)
      first = selections.first ? selections.first.clamp(0, count) : 0
      return (first...(first + fitting)) if first + fitting <= count

      ([0, count - fitting].max...count)
    end

    # iText also highlights a selection just below the last row it shows.
    def highlights(selections, rows, top, leading)
      inset = @border.inner_width
      selections.grep(rows.begin..rows.end).map do |index|
        "#{n(inset)} #{n(f(top - f(f(index - rows.begin + 1) * leading)))} " \
          "#{n(f(@width - f(2 * inset)))} #{n(leading)} re f "
      end.join
    end

    def list_rows(choices, selections, rows, size, top)
      x = f(@border.inner_width * 2)
      leading = f(@font.top(size) - @font.bottom(size))
      baseline = f(top - @font.top(size))
      rows.map do |index|
        color = selections.include?(index) ? "1 g" : @color
        chars = LineBreaker.rstrip(choices[index].gsub(/\r\n?|\n/, " ").chars)
        y = shown_y(baseline)
        baseline = f(baseline - leading)
        "#{color} ".b << text_object(size, [[x, y, chars]])
      end.join.b
    end

    def stream_for(widget, value)
      configure(widget)
      @border = Border.new(@widget, @width, @height, comb_cells: comb? ? max_length : 0)
      form_xobject("#{@border.appearance}/Tx BMC ".b << variable_text(value) << "EMC ".b)
    end

    # iText computes the box in single precision.
    def box(rect)
      llx, lly, urx, ury = rect.pack("e4").unpack("e4")
      [urx - llx, ury - lly].pack("e2").unpack("e2")
    end

    def variable_text(value)
      return "".b if value.empty?

      clip = [offset, offset, f(@width - f(2 * offset)), f(@height - f(2 * offset))].map { |number| n(number) }
      "q #{clip.join(" ")} re W n #{@color} ".b << text(value) << "Q ".b
    end

    # iText's offX: the clipping inset
    def offset = [@border.inner_width, padding].min

    # iText's offsetX: the text inset
    def padding = [@border.inner_width, 1].max

    # iText's h: the height inside the border
    def inner_height
      height = f(@height - f(@border.width * 2))
      @border.inner_width == @border.width ? height : f(height - f(@border.width * 2))
    end

    def text(value)
      return multiline_text(value) if multiline?

      chars = value.gsub(/\r\n?|\n/, " ").chars
      size = @font_size.zero? ? auto_size(chars) : f(@font_size)
      baseline = single_line_baseline(size)
      comb? ? comb_text(chars, size, baseline) : single_line_text(chars, size, baseline)
    end

    # iText's ColumnText#showTextAligned: a column of 20000 points from the anchor of the alignment.
    def single_line_text(chars, size, baseline)
      anchor = case alignment
               when :center then f(@width / 2)
               when :right then f(@width - f(2 * padding))
               else f(2 * padding)
               end
      left, right = case alignment
                    when :center then [f(anchor - 20_000), f(anchor + 20_000)]
                    when :right then [f(anchor - 20_000), anchor]
                    else [anchor, f(anchor + 20_000)]
                    end
      line = LineBreaker.new(chars, f(right - left)) { |char| @font.char_width(char, size) }.lines.first
      text_object(size, [[aligned_x(left, line.width_left), shown_y(baseline), line.chars]])
    end

    # PdfLine#indentLeft: the width left on the line moves it right, or half of it to the center.
    def aligned_x(left, width_left)
      case alignment
      when :center then f(left + f(width_left / 2))
      when :right then f(left + width_left)
      else left
      end
    end

    # ColumnText places the first line one leading (2 points) below the top of its column.
    def shown_y(baseline) = f(f(baseline + 2) - 2)

    def comb_text(chars, size, baseline)
      step = f(@width / max_length)
      start = f(f(step / 2) + f(comb_position(chars.size) * step))
      glyphs = chars.map do |char|
        x = f(start - f(@font.char_width(char, size) / 2))
        start = f(start + step)
        [x, baseline, [char]]
      end
      text_object(size, glyphs)
    end

    def comb_position(shown)
      free = max_length - [max_length, shown].min
      case alignment
      when :center then free / 2
      when :right then free
      else 0
      end
    end

    # iText's ColumnText in a column from 2 * offsetX to the width less 2 * offsetX, whose top is one
    # leading above the first baseline.
    def multiline_text(value)
      paragraphs = value.split(/\r\n|\r|\n/, -1).map(&:chars)
      size = @font_size.zero? ? multiline_auto_size(paragraphs) : f(@font_size)
      leading = f(size * @font.line_factor)
      left = f(2 * padding)
      width = f(f(@width - f(2 * padding)) - left)
      y = f(f(f(padding + inner_height) - @font.top(size)) + leading)
      glyphs = lines(paragraphs, size, width).map do |line|
        y = f(y - leading)
        [aligned_x(left, line.width_left), y, line.chars]
      end
      text_object(size, glyphs)
    end

    def lines(paragraphs, size, width)
      paragraphs.flat_map do |chars|
        LineBreaker.new(chars, width) { |char| @font.char_width(char, size) }.lines
      end
    end

    def text_object(size, glyphs)
      shown = glyphs.map { |x, y, chars| "1 0 0 1 #{n(x)} #{n(y)} Tm ".b << literal(chars) << " Tj".b }
      "BT #{PDF::Serializer.name(@font.key)} #{n(size)} Tf ".b << shown.join(" ").b << " ET ".b
    end

    # ColumnText#getWidth measures the text at size 1 in a 20000 point column: a text of whitespace
    # only is an empty line, measures 20000 and gets the smallest size.
    def auto_size(chars)
      max_size = f(inner_height / @font.auto_size_factor)
      line = LineBreaker.new(chars, 20_000) { |char| @font.char_width(char, 1) }.lines.first
      text_width = f(20_000 - line.width_left)
      return [max_size, MIN_AUTO_SIZE].max if text_width.zero?

      [max_size, f(f(@width - f(4 * padding)) / text_width)].min.clamp(MIN_AUTO_SIZE..)
    end

    # iText shrinks the text from at most 12 points in tenths of the range, until ColumnText fits it in
    # a column of the field's height.
    def multiline_auto_size(paragraphs)
      size = f(inner_height / @font.line_factor)
      return MIN_AUTO_SIZE if size <= MIN_AUTO_SIZE

      size = MULTILINE_MAX_AUTO_SIZE if size > MULTILINE_MAX_AUTO_SIZE
      step = [f(f(size - MIN_AUTO_SIZE) / 10), f(0.2)].max
      width = f(@width - f(4 * padding))
      size = f(size - step) while size > MIN_AUTO_SIZE && !fits?(paragraphs, size, width)
      [size, MIN_AUTO_SIZE].max
    end

    def fits?(paragraphs, size, width)
      leading = f(@font.line_factor * size)
      y = 0.0
      lines(paragraphs, size, width).all? do
        next false if f(y - leading) < -inner_height

        y = f(y - leading)
      end
    end

    def single_line_baseline(size)
      ascent = @font.ascent(size)
      descent = @font.descent(size)
      baseline = f(offset + f(f(f(@height - f(2 * offset)) - ascent) / 2))
      baseline = offset if baseline < offset
      return baseline unless f(baseline - offset) < -descent

      [f(-descent + offset), [baseline, f(f(@height - offset) - ascent)].max].min # rubocop:disable Style/ComparableClamp
    end

    def alignment = { 1 => :center, 2 => :right }.fetch(merged(:Q).to_i, :left)

    def max_length = merged(:MaxLen).to_i

    def comb? = merged(:Ff).to_i.anybits?(COMB) && max_length.positive?

    def multiline? = merged(:Ff).to_i.anybits?(MULTILINE)

    def literal(chars) = "(#{@font.encode_all(chars).pack("C*").gsub(/[()\\]/n) { |c| "\\#{c}" }})".b

    def n(number) = Fillform.number(number)

    def f(value) = Float32.f(value)
  end
end
