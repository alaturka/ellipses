# frozen_string_literal: true

module Foo
  module Support
    module_function

    def digest(*args)
      ::Digest::SHA256.hexdigest args.map(&:to_s).join
    end
  end
end
