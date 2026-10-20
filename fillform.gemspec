# frozen_string_literal: true

require_relative "lib/fillform/version"

Gem::Specification.new do |s|
  s.name = "fillform"
  s.version = Fillform::VERSION
  s.authors = ["Alessandro Rodi"]
  s.email = ["rodi@hey.com"]
  s.summary = "Fill PDF forms in pure Ruby, with the same output as pdftk. A drop-in replacement for pdf-forms."
  s.description = "Fills AcroForm templates in pure Ruby and draws the filled fields with the layout of pdftk " \
                  "(iText 2.1.7): no Java, no pdftk binary, no subprocess. Ships a PdfForms-compatible API."
  s.homepage = "https://github.com/coorasse/fillform"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.2"
  s.files = Dir["lib/**/*", "data/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  s.metadata = { "rubygems_mfa_required" => "true", "source_code_uri" => s.homepage,
                 "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md" }
end
