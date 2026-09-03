# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.setup

module Routing
  Error = Errors::Error
  InvariantError = Errors::InvariantError
  InvalidInputError = Errors::InvalidInputError

  def self.assert(condition, message)
    raise InvariantError, message unless condition
  end
end
