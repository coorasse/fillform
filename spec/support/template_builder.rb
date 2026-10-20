# frozen_string_literal: true

require "fillform"

# Writes AcroForm templates for the specs.
class TemplateBuilder
  MULTILINE = 1 << 12
  COMB = 1 << 24
  COMBO = 1 << 17
  RADIO = 1 << 15
  ALIGNMENTS = { left: 0, center: 1, right: 2 }.freeze

  def initialize
    @document = Fillform::PDF::Document.new
    @fields = []
    @pages = []
    @fonts = {
      Helv: font(:Helvetica, :WinAnsiEncoding), ZaDb: font(:ZapfDingbats, nil),
      Cour: font(:Courier, :WinAnsiEncoding), TiRo: font(:"Times-Roman", :WinAnsiEncoding)
    }
    page
  end

  # Starts a new page and returns its index.
  def page
    @pages << { Type: :Page, MediaBox: [0, 0, 595, 842], Resources: {}, Annots: [] }
    @pages.size - 1
  end

  def text_field(name, rect:, font_size: 0, font: :Helv, multiline: false, max_length: nil, comb: false,
                 alignment: :left, **)
    flags = (multiline ? MULTILINE : 0) | (comb ? COMB : 0)
    entries = { FT: :Tx, DA: "/#{font} #{font_size} Tf 0 g", Ff: flags, Q: ALIGNMENTS.fetch(alignment) }
    entries[:MaxLen] = max_length if max_length
    field(name, rect, entries, **)
  end

  def check_box(name, rect:, state: :Yes, radio: false, **)
    on_appearance = stream("q 0 g BT /ZaDb 8 Tf 1 1 Td (4) Tj ET Q", rect)
    appearances = { N: { state => on_appearance, Off: stream("", rect) }, D: { state => on_appearance } }
    field(name, rect, { FT: :Btn, Ff: radio ? RADIO : 0, V: :Off, AS: :Off, AP: appearances }, **)
  end

  def choice(name, rect:, options:, combo: true, font_size: 0, **other)
    options = options.map { |option| Array(option).map { |text| Fillform::PDF::Text.encode(text) } }
    options = options.map { |option| option.size == 1 ? option.first : option }
    entries = { FT: :Ch, Ff: combo ? COMBO : 0, DA: "/Helv #{font_size} Tf 0 g", Opt: options }
    field(name, rect, entries, **other)
  end

  def write(path)
    pages = @document.add({ Type: :Pages, Kids: [], Count: @pages.size })
    @pages.each do |page|
      page[:Parent] = pages
      @document.deref(pages)[:Kids] << @document.add(page)
    end
    form = { Fields: @fields, DA: "/Helv 0 Tf 0 g", DR: { Font: @fonts } }
    @document.trailer[:Root] = @document.add({ Type: :Catalog, Pages: pages, AcroForm: form })
    @document.write(path)
    path
  end

  private

  def field(name, rect, entries, page: 0, widget: {}, **extra)
    dictionary = { Type: :Annot, Subtype: :Widget, T: Fillform::PDF::Text.encode(name), Rect: rect, F: 4 }
    reference = @document.add(dictionary.merge(entries).merge(extra).merge(widget))
    @fields << reference
    @pages[page][:Annots] << reference
    reference
  end

  def font(name, encoding)
    @document.add({ Type: :Font, Subtype: :Type1, BaseFont: name, Encoding: encoding }.compact)
  end

  def stream(content, rect)
    width = rect[2] - rect[0]
    height = rect[3] - rect[1]
    @document.add(Fillform::PDF::Stream.new({ Type: :XObject, Subtype: :Form, BBox: [0, 0, width, height],
                                              Resources: { Font: { ZaDb: @fonts[:ZaDb] } } }, content.b))
  end
end
