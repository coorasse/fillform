# frozen_string_literal: true

require "spec_helper"

# The expected appearances were measured with pdftk 3.3 on the same templates.
RSpec.describe Fillform do
  describe ".fill" do
    it "sizes and positions a single line text like pdftk" do
      path = template { |form| form.text_field("name", rect: [0, 0, 120, 16], font_size: 10) }

      expect(shown_text(appearance(filled(path, { name: "Hans Müller" }), "name")))
        .to eq([[10, 2, 4.41, "Hans M\xFCller".b]])
    end

    it "keeps the leading spaces, drops the trailing ones and shows code 0 for missing glyphs" do
      path = template { |form| form.text_field("name", rect: [0, 0, 120, 16], font_size: 10) }

      expect(shown_text(appearance(filled(path, { name: "  Łódź €  " }), "name")))
        .to eq([[10, 2, 4.41, "  \x00\xF3d\x00 \x80".b]])
    end

    it "places the glyphs of a centered comb field in the middle cells" do
      path = template do |form|
        form.text_field("code", rect: [0, 0, 40, 12], comb: true, max_length: 4, alignment: :center)
      end

      expect(shown_text(appearance(filled(path, { code: "ab" }), "code")))
        .to eq([[9.8, 12.28, 2.48, "a".b], [9.8, 22.28, 2.48, "b".b]])
    end

    it "places the glyphs of a right aligned comb field in the last cells" do
      path = template do |form|
        form.text_field("code", rect: [0, 0, 40, 12], comb: true, max_length: 4, alignment: :right)
      end

      cells = shown_text(appearance(filled(path, { code: "ab" }), "code")).map { |_, x, _, _| (x / 10).floor }
      expect(cells).to eq([2, 3])
    end

    it "shrinks the text of a multiline field until it fits" do
      path = template { |form| form.text_field("address", rect: [0, 0, 130, 40], multiline: true) }
      address = "Hans Müller-Weiß\nBahnhofstrasse 12, 8001 Zürich\nSchweiz"

      expect(shown_text(appearance(filled(path, { address: address }), "address")))
        .to eq([[8.8, 2, 32.81, "Hans M\xFCller-Wei\xDF".b],
                [8.8, 2, 22.63, "Bahnhofstrasse 12, 8001 Z\xFCrich".b],
                [8.8, 2, 12.46, "Schweiz".b]])
    end

    it "sizes the text of a multiline field automatically between 4 and 12 points" do
      path = template do |form|
        form.text_field("tall", rect: [0, 0, 300, 100], multiline: true)
        form.text_field("flat", rect: [0, 0, 300, 3], multiline: true)
      end
      result = filled(path, { tall: "Hans Muster\nBahnhofstrasse 1", flat: "x" })

      expect(shown_text(appearance(result, "tall")).first.first).to eq(12)
      expect(shown_text(appearance(result, "flat")).first.first).to eq(4)
    end

    it "wraps lines after spaces and hyphens and drops the spaces at the start of a wrapped line" do
      path = template { |form| form.text_field("note", rect: [0, 0, 100, 60], multiline: true, font_size: 9) }
      note = "  Lorem ipsum dolor sit amet, consectetur-adipiscing  "

      expect(shown_text(appearance(filled(path, { note: note }), "note")))
        .to eq([[9, 2, 52.62, "  Lorem ipsum dolor sit".b], [9, 2, 42.22, "amet, consectetur-".b],
                [9, 2, 31.81, "adipiscing".b]])
    end

    it "draws the background and the border of the widget" do
      path = template do |form|
        form.text_field("name", rect: [0, 0, 120, 16], font_size: 10,
                                widget: { MK: { BG: [1, 1, 0.8], BC: [0, 0, 1] }, BS: { W: 2, S: :S } })
      end
      stream = appearance(filled(path, { name: "Hans" }), "name")

      expect(stream).to start_with("q 1 1 0.8 rg 0 0 120 16 re f 0 0 1 RG 2 w 1 1 118 14 re S Q ")
      expect(stream).to include("/Tx BMC q 2 2 116 12 re W n")
      expect(shown_text(stream)).to eq([[10, 4, 4.41, "Hans".b]])
    end

    it "draws with Helvetica and drops missing glyphs when the font is not in the form" do
      path = template { |form| form.text_field("name", rect: [0, 0, 120, 16], font_size: 10, font: :Missing) }

      expect(shown_text(appearance(filled(path, { name: "Łódź" }), "name"))).to eq([[10, 2, 4.41, "\xF3d".b]])
    end

    it "shows the text of the selected option of a combo box" do
      path = template do |form|
        form.choice("pick", rect: [0, 0, 120, 16], options: [%w[a Alpha], %w[b Beta]], font_size: 10)
      end
      result = filled(path, { pick: "b" })

      expect(shown_text(appearance(result, "pick"))).to eq([[10, 2, 4.41, "Beta".b]])
      expect(field(result, "pick")[:V]).to eq("b")
    end

    it "checks and unchecks check boxes" do
      path = template do |form|
        form.check_box("yes", rect: [0, 0, 10, 10])
        form.check_box("no", rect: [20, 0, 30, 10])
      end
      result = filled(path, { yes: "Yes", no: "Off" })

      expect(field(result, "yes")[:V]).to eq(:Yes)
      expect(field(result, "yes").widgets.first[:AS]).to eq(:Yes)
      expect(field(result, "no").widgets.first[:AS]).to eq(:Off)
    end

    it "leaves a check box as it is for an unknown state" do
      path = template { |form| form.check_box("box", rect: [0, 0, 10, 10]) }
      result = filled(path, { box: "Maybe" })

      expect(field(result, "box")[:V]).to eq(:Off)
      expect(field(result, "box").widgets.first[:AS]).to eq(:Off)
    end

    it "matches a state name given as pdftk shows it, in Latin-1" do
      path = template { |form| form.check_box("box", rect: [0, 0, 10, 10], state: :Sì) }

      expect(field(filled(path, { box: "SÃ¬" }), "box")[:V].to_s.b).to eq("Sì".b)
    end

    it "draws the appearances into the pages and removes the fields when flattening" do
      path = template do |form|
        form.text_field("name", rect: [10, 20, 130, 36], font_size: 10)
        form.check_box("box", rect: [10, 40, 20, 50])
      end
      document = Fillform::PDF::Document.open(filled(path, { name: "Hans", box: "Yes" }, flatten: true))
      page = document.pages.first[1]

      expect(page).not_to have_key(:Annots)
      expect(Fillform::Form.new(document).fields).to be_empty
      expect(document.deref(page[:Contents].last).data(document))
        .to eq("\nQ\nq 1 0 0 1 10 40 cm /Xi0 Do Q\nq 1 0 0 1 10 20 cm /Xi1 Do Q\n")
    end

    it "ignores the values of fields the template does not have" do
      path = template { |form| form.text_field("name", rect: [0, 0, 120, 16]) }

      expect { filled(path, { unknown: "x", name: "Hans" }) }.not_to raise_error
    end
  end

  describe ".fields" do
    it "describes the fields like pdftk dump_data_fields" do
      path = template do |form|
        form.text_field("name", rect: [0, 0, 120, 16], TU: " Name", DV: "", V: "  Hans")
        form.text_field("code", rect: [0, 20, 40, 32], comb: true, max_length: 4, alignment: :right)
        form.check_box("box", rect: [0, 40, 10, 50])
      end

      expect(described_class.fields(path).map(&:to_h)).to eq(
        [{ name: "name", type: "Text", options: nil, flags: "0", justification: "Left", value: "Hans",
           value_default: nil, name_alt: "Name", max_length: nil },
         { name: "code", type: "Text", options: nil, flags: "16777216", justification: "Right", value: nil,
           value_default: nil, name_alt: nil, max_length: "4" },
         { name: "box", type: "Button", options: %w[Off Yes], flags: "0", justification: "Left", value: "Off",
           value_default: nil, name_alt: nil, max_length: nil }]
      )
    end
  end
end
