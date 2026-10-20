# frozen_string_literal: true

require "fillform"
require_relative "data_format"
require_relative "pdftk_wrapper"

# The API of the pdf-forms gem, backed by Fillform. `gem "fillform", require: "fillform/pdf_forms"`
# replaces `gem "pdf-forms"` without changing the code that calls it.
module PdfForms
  PdftkError = Fillform::Error

  def self.new(*)
    Fillform::PdftkWrapper.new(*)
  end
end
