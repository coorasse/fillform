# frozen_string_literal: true

require "fillform"
require "securerandom"
require "tmpdir"
require_relative "support/templates"

RSpec.configure do |config|
  config.include Templates
  config.around do |example|
    Dir.mktmpdir("fillform") do |dir|
      @tmp = dir
      example.run
    end
  end
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.order = :random
end
