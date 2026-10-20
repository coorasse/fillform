# frozen_string_literal: true

require "spec_helper"
require "fillform/pdf_forms"

RSpec.describe PdfForms do
  let(:path) do
    template do |form|
      form.text_field("name", rect: [0, 0, 120, 16], font_size: 10)
      form.text_field("address", rect: [0, 20, 200, 80], font_size: 10, multiline: true)
      form.text_field("person_city", rect: [0, 90, 120, 106], font_size: 10)
      form.check_box("box", rect: [0, 110, 10, 120])
    end
  end
  let(:destination) { tmp_path("filled.pdf") }

  it "takes the arguments of pdf-forms and ignores the pdftk path" do
    expect(described_class.new("/usr/bin/pdftk", data_format: "XFdf").options).to eq(data_format: "XFdf")
    expect(described_class.new(flatten: true).options).to eq(flatten: true)
    expect(described_class.new.options).to eq({})
  end

  it "fills and flattens a form" do
    described_class.new("/usr/bin/pdftk").fill_form(path, destination, { name: "Hans", box: "Yes" }, flatten: true)

    expect(Fillform.fields(destination)).to be_empty
  end

  it "flattens when the wrapper was created with the option" do
    described_class.new(flatten: true).fill_form(path, destination, { name: "Hans" })

    expect(Fillform.fields(destination)).to be_empty
  end

  it "fills the fields of a nested hash like pdf-forms" do
    described_class.new.fill_form(path, destination, { person: { city: "Bern" } })

    expect(value(destination, "person_city")).to eq("Bern")
  end

  it "reads the fields of a template" do
    pdftk = described_class.new("/usr/bin/pdftk")

    expect(pdftk.get_field_names(path)).to eq(%w[name address person_city box])
    expect(pdftk.get_fields(path).map(&:type)).to eq(%w[Text Text Text Button])
    expect(pdftk.read(path).field("box").options).to eq(%w[Off Yes])
  end

  it "raises for a template that cannot be read" do
    expect { described_class.new.get_fields(tmp_path("missing.pdf")) }.to raise_error(IOError)
  end

  it "raises for the pdftk options it does not support" do
    expect { described_class.new(encrypt: true) }.to raise_error(Fillform::Error, /encrypt/)
    expect { described_class.new.fill_form(path, destination, {}, drop_xfa: true) }
      .to raise_error(described_class::PdftkError, /drop_xfa/)
  end

  # Fdf, the default of pdf-forms, writes the values in ISO-8859-15 that pdftk reads in PDFDocEncoding.
  it "changes the values like the Fdf data format" do
    described_class.new.fill_form(path, destination, { name: "1 € œ ł", address: "a\nb" })

    expect(value(destination, "name")).to eq("1€¤ ½ ?")
    expect(value(destination, "address")).to eq("a\rb")
  end

  it "changes the values like the XFdf data format" do
    described_class.new(data_format: "XFdf").fill_form(path, destination, { name: "a  b", address: "a\n\n\nb\r\nc" })

    expect(value(destination, "name")).to eq("a b")
    expect(value(destination, "address")).to eq("a\nb\nc")
  end

  it "keeps the values with the FdfHex data format" do
    described_class.new(data_format: "FdfHex").fill_form(path, destination, { name: "1 €", address: "a\n\nb" })

    expect(value(destination, "name")).to eq("1 €")
    expect(value(destination, "address")).to eq("a\n\nb")
  end
end
