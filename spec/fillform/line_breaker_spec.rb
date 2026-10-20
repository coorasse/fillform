# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fillform::LineBreaker do
  def lines(text, width)
    described_class.new(text.chars, width) { 1 }.lines.map { |line| line.chars.join }
  end

  it "breaks after the last space that fits" do
    expect(lines("aaa bbb ccc", 7)).to eq(["aaa bbb", "ccc"])
  end

  it "breaks after a hyphen" do
    expect(lines("aaa-bbb", 5)).to eq(["aaa-", "bbb"])
  end

  it "moves a hyphen that does not fit to the next line" do
    expect(lines("aaa bbb-ccc", 7)).to eq(["aaa bbb", "-ccc"])
  end

  it "breaks a word longer than the line" do
    expect(lines("abcdefgh", 3)).to eq(%w[abc def gh])
  end

  it "keeps the leading spaces of the paragraph only" do
    expect(lines("  aa bb   cc", 5)).to eq(["  aa", "bb", "cc"])
  end

  it "keeps a line of spaces broken before a word" do
    expect(lines(" abcdef", 3)).to eq([" ", "abc", "def"])
  end

  it "returns an empty line for an empty paragraph" do
    expect(lines("", 3)).to eq([""])
  end
end
