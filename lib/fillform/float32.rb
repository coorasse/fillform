# frozen_string_literal: true

module Fillform
  # iText computes the layout with Java floats: each operation is rounded to single precision.
  module Float32
    module_function

    def f(value) = [value].pack("e").unpack1("e")

    THOUSANDTH = f(0.001)
  end
end
