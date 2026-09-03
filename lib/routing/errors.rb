# frozen_string_literal: true

module Routing
  module Errors
    class Error < StandardError
    end

    class InvariantError < Error
    end

    class InvalidInputError < Error
    end
  end
end
