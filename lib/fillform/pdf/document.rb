# frozen_string_literal: true

module Fillform
  module PDF
    # A PDF file as a store of indirect objects. Objects are read when they are first used, and
    # writing a document writes every object reachable from the trailer, as a single revision.
    class Document
      Entry = Struct.new(:type, :position, :index)

      attr_reader :trailer, :version

      def self.open(path) = new(File.binread(path))

      def initialize(data = nil)
        @objects = {}
        @entries = {}
        @object_streams = {}
        if data
          @data = data.b
          @version = @data[/\A%PDF-(\d\.\d)/, 1] || "1.4"
          load_cross_references
        else
          @version = "1.7"
          @trailer = {}
        end
      end

      def deref(value)
        value.is_a?(Reference) ? object(value.number) : value
      end

      def object(number)
        return @objects[number] if @objects.key?(number)

        @objects[number] = read_object(number)
      end

      def add(value)
        number = [@entries.keys.max.to_i, @objects.keys.max.to_i].max + 1
        @objects[number] = value
        Reference.new(number, 0)
      end

      def catalog = deref(@trailer[:Root])

      def pages
        result = []
        collect_pages(catalog[:Pages], {}, result)
        result
      end

      def write(path)
        File.binwrite(path, Writer.new(self, reachable).to_pdf)
      end

      # Object numbers reachable from the trailer, in ascending order.
      def reachable
        seen = {}
        pending = [@trailer[:Root], @trailer[:Info]].compact
        until pending.empty?
          value = pending.pop
          case value
          when Reference
            next if seen.key?(value.number)

            seen[value.number] = true
            pending << object(value.number)
          when Hash then pending.concat(value.values)
          when Array then pending.concat(value)
          when Stream then pending.concat(value.dictionary.values)
          end
        end
        seen.keys.select { |number| @objects.key?(number) && !@objects[number].nil? }.sort
      end

      private

      INHERITED_PAGE_KEYS = %i[Resources MediaBox CropBox Rotate].freeze

      # [reference, page dictionary, inherited attributes] in page order.
      def collect_pages(reference, inherited, result, depth = 0)
        node = deref(reference)
        return unless node.is_a?(Hash) && depth < 64

        if node[:Type] == :Pages || node.key?(:Kids)
          inherited = inherited.merge(node.slice(*INHERITED_PAGE_KEYS))
          Array(deref(node[:Kids])).each { |kid| collect_pages(kid, inherited, result, depth + 1) }
        else
          result << [reference, node, inherited]
        end
      end

      def read_object(number)
        entry = @entries[number]
        return nil unless entry.is_a?(Entry)

        entry.type == :compressed ? compressed_object(entry.position, entry.index) : object_at(number, entry.position)
      rescue MalformedError
        raise if @rebuilt

        rebuild_cross_references
        @objects.delete(number)
        read_object(number)
      end

      def object_at(number, position)
        parser = Parser.new(@data, position) { |length| deref(length) }
        found, _generation, value = parser.parse_indirect
        raise MalformedError, "object #{number} is not at #{position}" unless found == number

        value
      end

      def compressed_object(stream_number, index)
        offsets, data = object_stream(stream_number)
        return nil unless offsets && index < offsets.size

        Parser.new(data, offsets[index][1]).parse_object
      end

      def object_stream(number)
        @object_streams[number] ||= begin
          stream = object(number)
          data = stream.data(self)
          first = stream[:First].to_i
          header = Parser.new(data)
          pairs = Array.new(stream[:N].to_i) { [header.parse_object, first + header.parse_object] }
          [pairs, data]
        end
      end

      def load_cross_references
        position = @data.rindex("startxref") or return rebuild_cross_references
        position = @data[(position + 9)..][/\A\s*(\d+)/, 1].to_i
        visited = {}
        until position.nil? || visited.key?(position)
          visited[position] = true
          trailer = read_section(position)
          @trailer ||= trailer
          read_section(trailer[:XRefStm]) if trailer[:XRefStm].is_a?(Integer)
          position = trailer[:Prev]
        end
        raise MalformedError, "no catalog" unless @trailer && @trailer[:Root]
      rescue MalformedError, ArgumentError, NoMethodError, TypeError
        rebuild_cross_references
      ensure
        raise Fillform::Error, "encrypted PDF files are not supported" if @trailer&.key?(:Encrypt)
      end

      def read_section(position)
        parser = Parser.new(@data, position)
        parser.skip_whitespace
        parser.scanner.skip(/xref\b/) ? read_table(parser) : read_stream_section(parser)
      end

      def read_table(parser)
        scanner = parser.scanner
        while scanner.skip(/\s*(\d+)\s+(\d+)[ \t]*[\r\n]+/)
          first = scanner[1].to_i
          scanner[2].to_i.times do |i|
            scanner.skip(/\s*(\d+)\s+(\d+)\s+([nf])/) or raise MalformedError, "broken cross-reference table"
            register(first + i, Entry.new(:offset, scanner[1].to_i)) if scanner[3] == "n"
            register(first + i, :free) if scanner[3] == "f"
          end
        end
        scanner.skip(/\s*trailer/) or raise MalformedError, "no trailer"
        parser.parse_object
      end

      def read_stream_section(parser)
        _number, _generation, stream = parser.parse_indirect
        raise MalformedError, "no cross-reference stream" unless stream.is_a?(Stream) && stream[:Type] == :XRef

        widths = stream[:W]
        index = stream[:Index] || [0, stream[:Size]]
        data = stream.data(self).bytes
        index.each_slice(2).with_object(data) do |(first, count), bytes|
          count.times do |i|
            fields = widths.map { |width| bytes.shift(width).reduce(0) { |sum, byte| (sum << 8) | byte } }
            register_stream_entry(first + i, widths[0].zero? ? 1 : fields[0], fields[1], fields[2])
          end
        end
        stream.dictionary
      end

      def register_stream_entry(number, type, field, index)
        case type
        when 0 then register(number, :free)
        when 1 then register(number, Entry.new(:offset, field))
        when 2 then register(number, Entry.new(:compressed, field, index))
        end
      end

      # The newest revision is read first, so an object keeps its first entry.
      def register(number, entry)
        @entries[number] = entry unless @entries.key?(number)
      end

      # Finds the objects by scanning the file, like readers do with a broken cross-reference table.
      def rebuild_cross_references
        @rebuilt = true
        @entries = {}
        @objects.clear
        @object_streams.clear
        @data.scan(/(?<!\d)(\d+)\s+(\d+)\s+obj\b/) do
          @entries[::Regexp.last_match(1).to_i] = Entry.new(:offset, ::Regexp.last_match.begin(0))
        end
        @entries.to_a.each { |number, entry| register_compressed_objects(number, entry.position) }
        @trailer = rebuilt_trailer or raise MalformedError, "no catalog found"
      end

      # The object that comes last in the file is the newest one.
      def register_compressed_objects(number, position)
        stream = object(number)
        return unless stream.is_a?(Stream) && stream[:Type] == :ObjStm

        object_stream(number)[0].each_with_index do |(member, _offset), index|
          current = @entries[member]
          newer = current.nil? || position > file_position(current)
          @entries[member] = Entry.new(:compressed, number, index) if newer
        end
      rescue MalformedError
        nil
      end

      def file_position(entry) = entry.type == :offset ? entry.position : @entries[entry.position].position

      def rebuilt_trailer
        position = @data.rindex(/trailer\s*<</)
        trailer = position ? Parser.new(@data, @data.index("<<", position)).parse_object : {}
        return trailer if deref(trailer[:Root]).is_a?(Hash)

        catalog = @entries.keys.find { |number| object(number).is_a?(Hash) && object(number)[:Type] == :Catalog }
        catalog && trailer.merge(Root: Reference.new(catalog, 0))
      rescue MalformedError
        nil
      end
    end
  end
end
