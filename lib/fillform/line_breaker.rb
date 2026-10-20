# frozen_string_literal: true

module Fillform
  # Breaks a paragraph into lines like iText's BidiLine: the paragraph loses its trailing whitespace,
  # a line ends after the last split character before the first character that does not fit, or
  # before that character, and only the first line keeps its leading whitespace. Each line comes with
  # the width left on it, computed in floats like iText does, which aligns it.
  class LineBreaker
    NO_PRINT = /[​-‏‪-‮]/
    CJK = /[⺀-힟豈-﫿︰-﹏｡-ﾟ]/

    Line = Struct.new(:chars, :width_left)

    def self.whitespace?(char) = char <= " "

    def self.blank?(char) = whitespace?(char) || NO_PRINT.match?(char)

    def self.rstrip(chars)
      last = chars.rindex { |char| !blank?(char) }
      last ? chars[0..last] : []
    end

    def initialize(chars, width, &char_width)
      @chars = self.class.rstrip(chars)
      @width = Float32.f(width)
      @char_width = char_width
    end

    def lines
      return [Line.new([], 0.0)] if @chars.empty?

      result = []
      position = 0
      while position < @chars.size
        position += 1 while position.positive? && position < @chars.size && self.class.blank?(@chars[position])
        break if position == @chars.size

        line, position = next_line(position)
        result << line
      end
      result
    end

    private

    # The branches of BidiLine#processLine, with the width each one leaves.
    def next_line(start)
      fitting, last_split, left = scan(start)
      return [Line.new(@chars[start..], left), @chars.size] if fitting == @chars.size
      return [Line.new([@chars[start]], 0.0), start + 1] if fitting == start

      last = last_visible(start, fitting - 1)
      return [Line.new(@chars[start...fitting], left), fitting] if last < start
      if last_split.nil? || last_split >= last
        return [Line.new(@chars[start..last], f(left + width(last + 1, fitting - 1))), fitting]
      end

      split_last = last_visible(start, last_split)
      split_last = last_split if split_last < start
      [Line.new(@chars[start..split_last], f(@width - width(start, split_last))), last_split + 1]
    end

    # The index of the first character that does not fit, the last split character up to it, and the
    # width left.
    def scan(start)
      left = @width
      last_split = nil
      index = start
      while index < @chars.size
        char = @chars[index]
        unless NO_PRINT.match?(char)
          char_width = @char_width.call(char)
          last_split = index if split?(char)
          break if f(left - char_width).negative?

          left = f(left - char_width)
        end
        index += 1
      end
      [index, last_split, left]
    end

    # BidiLine#getWidth
    def width(first, last)
      (first..last).reduce(0.0) do |sum, index|
        NO_PRINT.match?(@chars[index]) ? sum : f(sum + @char_width.call(@chars[index]))
      end
    end

    def last_visible(start, finish)
      finish.downto(start).find { |index| !self.class.blank?(@chars[index]) } || (start - 1)
    end

    def split?(char) = char <= " " || char == "-" || CJK.match?(char)

    def f(value) = Float32.f(value)
  end
end
