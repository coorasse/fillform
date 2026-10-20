# frozen_string_literal: true

require "strscan"

module Fillform
  module PDF
    # Reads PDF objects and content stream operations from bytes.
    class Parser
      WHITESPACE = /(?:[\0\t\n\f\r ]+|%[^\r\n]*)+/
      REGULAR = %r{[^\0\t\n\f\r ()<>\[\]{}/%]+}
      NUMBER = /[+-]?(?:\d+\.?\d*|\.\d+)\z/
      REFERENCE = %r{(\d+)[\0\t\n\f\r ]+(\d+)[\0\t\n\f\r ]+R(?=[\0\t\n\f\r ()<>\[\]{}/%]|\z)}
      ESCAPES = { "n" => "\n", "r" => "\r", "t" => "\t", "b" => "\b", "f" => "\f" }.freeze
      Keyword = Struct.new(:name)

      attr_reader :scanner

      # The length resolver turns an indirect /Length of a stream into a number.
      def initialize(data, position = 0, &length_resolver)
        @scanner = StringScanner.new(data)
        @scanner.pos = position
        @length_resolver = length_resolver
      end

      def position = @scanner.pos

      # An indirect object at the current position: [number, generation, value].
      def parse_indirect
        skip_whitespace
        @scanner.scan(/(\d+)\s+(\d+)\s+obj\b/) or raise MalformedError, "no object at #{position}"
        number = @scanner[1].to_i
        generation = @scanner[2].to_i
        [number, generation, stream_after(parse_object)]
      end

      def parse_object
        token = next_token
        raise MalformedError, "unexpected end of data" if token.equal?(:eof)
        if token.is_a?(Keyword) && !token.name.match?(/\A(true|false|null)\z/)
          raise MalformedError,
                "unexpected #{token.name}"
        end

        token.is_a?(Keyword) ? keyword_value(token.name) : token
      end

      # Content stream operations: [operator, operands].
      def each_operation
        operands = []
        loop do
          token = next_token
          break if token.equal?(:eof)

          if token.is_a?(Keyword) && !%w[true false null].include?(token.name)
            yield token.name.to_sym, operands
            skip_inline_image if token.name == "ID"
            operands = []
          else
            operands << (token.is_a?(Keyword) ? keyword_value(token.name) : token)
          end
        end
      end

      def next_token
        skip_whitespace
        return :eof if @scanner.eos?

        return Reference.new(@scanner[1].to_i, @scanner[2].to_i) if @scanner.scan(REFERENCE)

        case @scanner.peek(1)
        when "/" then name
        when "(" then literal_string
        when "<" then @scanner.peek(2) == "<<" ? dictionary : hex_string
        when "[" then array
        when "]", ">", ")", "{", "}"
          raise MalformedError, "unexpected #{@scanner.getch} at #{position}"
        else word
        end
      end

      def skip_whitespace = @scanner.skip(WHITESPACE)

      private

      def keyword_value(word)
        { "true" => true, "false" => false, "null" => nil }.fetch(word)
      end

      def word
        text = @scanner.scan(REGULAR) or raise MalformedError, "unexpected #{@scanner.getch.inspect} at #{position}"
        return Keyword.new(text) unless text.match?(NUMBER)

        text.include?(".") ? text.to_f : text.to_i
      end

      def name
        @scanner.getch
        text = (@scanner.scan(REGULAR) || "").b
        text.gsub(/#(\h\h)/) { ::Regexp.last_match(1).hex.chr }.to_sym
      end

      def array
        @scanner.getch
        result = []
        loop do
          skip_whitespace
          raise MalformedError, "unterminated array" if @scanner.eos?
          break @scanner.getch if @scanner.peek(1) == "]"

          result << parse_object
        end
        result
      end

      def dictionary
        @scanner.pos += 2
        result = {}
        loop do
          skip_whitespace
          raise MalformedError, "unterminated dictionary" if @scanner.eos?
          break @scanner.pos += 2 if @scanner.peek(2) == ">>"

          key = next_token
          raise MalformedError, "dictionary key #{key.inspect} is not a name" unless key.is_a?(Symbol)

          skip_whitespace
          result[key] = @scanner.peek(2) == ">>" ? nil : parse_object
        end
        result
      end

      def hex_string
        @scanner.getch
        digits = @scanner.scan_until(/>/) or raise MalformedError, "unterminated hex string"
        digits = digits.delete("^0-9A-Fa-f")
        [digits.length.odd? ? "#{digits}0" : digits].pack("H*")
      end

      def literal_string
        @scanner.getch
        result = +"".b
        depth = 1
        loop do
          chunk = @scanner.scan(/[^()\\]+/)
          result << chunk.b.gsub(/\r\n?/, "\n") if chunk
          char = @scanner.getch or raise MalformedError, "unterminated string"
          case char
          when "(" then depth += 1
                        result << "("
          when ")"
            depth -= 1
            break if depth.zero?

            result << ")"
          else result << escape
          end
        end
        result
      end

      def escape
        if (octal = @scanner.scan(/[0-7]{1,3}/))
          (octal.to_i(8) & 0xFF).chr
        elsif @scanner.skip(/\r\n?|\n/)
          ""
        else
          char = @scanner.getch.to_s
          ESCAPES.fetch(char, char).b
        end
      end

      def stream_after(value)
        return value unless value.is_a?(Hash)

        skip_whitespace
        return value unless @scanner.skip(/stream\r?\n/)

        Stream.new(value, stream_data(value))
      end

      def stream_data(dictionary)
        start = position
        length = dictionary[:Length]
        length = @length_resolver&.call(length) if length.is_a?(Reference)
        if length_valid?(start, length)
          @scanner.pos = start + length
        elsif !@scanner.scan_until(/(?=\r?\n?endstream)/)
          raise MalformedError, "unterminated stream"
        end
        data = @scanner.string.byteslice(start, position - start)
        @scanner.skip(/\s*endstream/)
        data
      end

      def length_valid?(start, length)
        length.is_a?(Integer) && @scanner.string.byteslice(start + length, 30).to_s.match?(/\A\s*endstream/)
      end

      def skip_inline_image
        @scanner.getch
        @scanner.scan_until(/[\0\t\n\f\r ]EI(?=[\0\t\n\f\r ]|\z)/)
      end
    end
  end
end
