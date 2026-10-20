# frozen_string_literal: true

require_relative "template_builder"

# Builds templates and reads the appearances Fillform fills in.
module Templates
  def tmp_path(name) = File.join(@tmp, name)

  def template
    builder = TemplateBuilder.new
    yield builder
    builder.write(tmp_path("template-#{SecureRandom.hex(4)}.pdf"))
  end

  def filled(path, values, flatten: false)
    destination = path.sub(".pdf", "-filled.pdf")
    Fillform.fill(path, destination, values, flatten: flatten)
    destination
  end

  def form(path) = Fillform::Form.new(Fillform::PDF::Document.open(path))

  def field(path, name) = form(path).field(name)

  def value(path, name) = Fillform::PDF::Text.decode(field(path, name)[:V])

  def appearance(path, name)
    form = form(path)
    form.document.deref(form.field(name).widgets.first[:AP][:N]).data(form.document)
  end

  # The text shown by the appearance: [font size, x, y, string] for each Tj.
  def shown_text(stream)
    size = nil
    position = nil
    shown = []
    Fillform::PDF::Parser.new(stream).each_operation do |operator, operands|
      case operator
      when :Tf then size = operands[1]
      when :Tm then position = operands[4..5]
      when :Tj then shown << [size, *position, operands[0].b]
      end
    end
    shown
  end
end
