# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fillform::PDF::Parser do
  def parse(text) = described_class.new(text.b).parse_object

  it "reads dictionaries, arrays, numbers, references and keywords" do
    expect(parse("<< /A [1 -2.5 .5 3 0 R] /B true /C null /D << /E /F >> >>"))
      .to eq(A: [1, -2.5, 0.5, Fillform::PDF::Reference.new(3, 0)], B: true, C: nil, D: { E: :F })
  end

  it "reads the escapes of literal strings and normalizes their line ends" do
    expect(parse("(a\\(b\\)\\\\ \\101\\n\\\r\nc(d)\r\ne)")).to eq("a(b)\\ A\nc(d)\ne".b)
  end

  it "reads hex strings and names with escapes" do
    expect(parse("<4142 43>")).to eq("ABC")
    expect(parse("/Ja#20Oui")).to eq(:"Ja Oui")
  end

  it "reads the operations of a content stream" do
    operations = []
    described_class.new("q 1 0 0 1 2 3 cm BT /F1 9 Tf (Hi) Tj ET Q".b).each_operation do |operator, operands|
      operations << [operator, operands]
    end

    expect(operations).to eq([[:q, []], [:cm, [1, 0, 0, 1, 2, 3]], [:BT, []], [:Tf, [:F1, 9]], [:Tj, ["Hi"]],
                              [:ET, []], [:Q, []]])
  end
end
