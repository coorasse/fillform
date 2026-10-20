# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fillform::PDF::Document do
  # A file like the templates of form designers: objects in an object stream, a cross-reference stream
  # with the PNG Up predictor, and an incremental update that changes an object.
  def updated_file
    out = +"%PDF-1.6\n".b
    offsets = {}
    add = lambda do |number, body|
      offsets[number] = out.bytesize
      out << "#{number} 0 obj\n#{body}\nendobj\n".b
    end
    add.call(1, "<< /Type /Catalog /Pages 2 0 R >>")
    add.call(2, "<< /Type /Pages /Kids [5 0 R] /Count 1 >>")
    members = { 3 => "(old)", 4 => "<< /Note 3 0 R >>" }
    header = members.keys.zip(members.values.each_with_object([0]) { |body, sums| sums << (sums.last + body.size + 1) })
                    .map { |number, offset| "#{number} #{offset}" }.join(" ")
    data = "#{header} #{members.values.join(" ")} "
    first = header.size + 1
    add.call(6, stream("/Type /ObjStm /N 2 /First #{first}", Zlib::Deflate.deflate(data), filter: true))
    add.call(5, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Extra 4 0 R >>")
    entries = { 0 => [0, 0, 255], 1 => [1, offsets[1], 0], 2 => [1, offsets[2], 0], 3 => [2, 6, 0],
                4 => [2, 6, 1], 5 => [1, offsets[5], 0], 6 => [1, offsets[6], 0] }
    xref = out.bytesize
    add.call(7, xref_stream(entries.merge(7 => [1, xref, 0]), "/Size 8 /Root 1 0 R"))
    out << "startxref\n#{xref}\n%%EOF\n"
    add.call(3, "(new)")
    update = out.bytesize
    add.call(8, xref_stream({ 3 => [1, offsets[3], 0], 8 => [1, update, 0] },
                            "/Size 9 /Root 1 0 R /Prev #{xref} /Index [3 1 8 1]"))
    out << "startxref\n#{update}\n%%EOF\n"
  end

  def xref_stream(entries, dictionary)
    rows = entries.sort.map { |_number, (type, field, index)| [type, field >> 8, field & 0xFF, index] }
    previous = [0, 0, 0, 0]
    encoded = rows.map do |row|
      line = [2] + row.zip(previous).map { |value, above| (value - above) & 0xFF }
      previous = row
      line
    end
    stream("/Type /XRef #{dictionary} /W [1 2 1] /DecodeParms << /Columns 4 /Predictor 12 >>",
           Zlib::Deflate.deflate(encoded.flatten.pack("C*")), filter: true)
  end

  def stream(dictionary, data, filter: false)
    "<< #{dictionary}#{" /Filter /FlateDecode" if filter} /Length #{data.bytesize} >>\nstream\n".b + data.b +
      "\nendstream".b
  end

  it "reads objects from object streams through cross-reference streams, newest revision first" do
    document = described_class.new(updated_file)

    expect(document.object(3)).to eq("new")
    expect(document.deref(document.object(4)[:Note])).to eq("new")
    expect(document.pages.size).to eq(1)
  end

  it "finds the objects by scanning the file when the cross-reference offset is wrong" do
    broken = updated_file.sub(/startxref\n(\d+)\n%%EOF\n\z/) do
      "startxref\n#{Regexp.last_match(1).to_i + 3}\n%%EOF\n"
    end
    document = described_class.new(broken)

    expect(document.object(3)).to eq("new")
    expect(document.catalog[:Type]).to eq(:Catalog)
  end

  it "writes the reachable objects as one revision" do
    path = tmp_path("written.pdf")
    described_class.new(updated_file).write(path)
    written = File.binread(path)
    document = described_class.open(path)

    expect(written.scan("%%EOF").size).to eq(1)
    expect(written).not_to include("/ObjStm")
    expect(document.deref(document.object(4)[:Note])).to eq("new")
  end

  it "refuses encrypted files" do
    encrypted = updated_file.sub("/Size 9 /Root 1 0 R", "/Size 9 /Root 1 0 R /Encrypt 1 0 R")

    expect { described_class.new(encrypted) }.to raise_error(Fillform::Error, /encrypted/)
  end
end
