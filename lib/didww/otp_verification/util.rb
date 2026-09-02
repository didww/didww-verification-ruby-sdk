module DIDWW
  module OTPVerification
    # Small internal helpers shared across the SDK.
    module Util
      module_function

      # @return [Boolean] true when +value+ is nil or an empty string.
      def blank?(value)
        value.nil? || value.to_s.empty?
      end
    end
  end
end
