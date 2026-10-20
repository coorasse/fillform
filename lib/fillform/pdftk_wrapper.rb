# frozen_string_literal: true

module Fillform
  class PdftkWrapper
    UNSUPPORTED_OPTIONS = %i[encrypt encrypt_password encrypt_options replacement_font drop_xfa drop_xmp
                             need_appearances].freeze

    attr_reader :options

    # The path of the pdftk executable, if given, is ignored: pdftk is no longer needed.
    def initialize(pdftk_or_options = nil, options = {})
      @options = pdftk_or_options.is_a?(Hash) ? pdftk_or_options : options
      check_options(@options)
    end

    # The values change on their way into the form like they do through the pdf-forms data format.
    def fill_form(template, destination, data = {}, fill_options = {})
      check_options(fill_options)
      flatten = fill_options.fetch(:flatten, options[:flatten])
      Fillform.fill(template, destination, encode(data), flatten: flatten ? true : false)
    end

    def read(path)
      Pdf.new(path)
    end

    def get_fields(template)
      read(template).fields
    end

    def get_field_names(template)
      get_fields(template).map(&:name)
    end

    private

    def encode(data)
      data.each_with_object({}) do |(key, value), result|
        if value.is_a?(Hash)
          value.each { |sub_key, sub_value| result[name("#{key}_#{sub_key}")] = encode_value(sub_value) }
        else
          result[name(key.to_s)] = encode_value(value)
        end
      end
    end

    def format = options[:data_format] || "Fdf"

    def name(key) = DataFormat.field_name(format, key)

    def encode_value(value)
      # pdf-forms writes the values of an array in one XFDF value, separated by spaces.
      value = value.join(" ") if value.is_a?(Array) && format.to_s == "XFdf"
      return value.map { |item| DataFormat.apply(format, item.to_s) } if value.is_a?(Array)

      DataFormat.apply(format, value.to_s)
    end

    def check_options(options)
      unsupported = options.keys.map(&:to_sym) & UNSUPPORTED_OPTIONS
      raise Error, "Fillform does not support the pdftk options #{unsupported.join(", ")}" if unsupported.any?
    end
  end

  class Pdf
    attr_reader :path

    def initialize(path)
      @path = path.to_s
      raise IOError, "#{@path} is not readable" unless File.readable?(@path)
    end

    def fields
      @fields ||= Fillform.fields(path)
    end

    def field(name)
      fields.find { |field| field.name == name }
    end
  end
end
