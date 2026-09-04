# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI")
loader.setup

module Routing
  Error = Errors::Error
  InvariantError = Errors::InvariantError
  InvalidInputError = Errors::InvalidInputError

  def self.assert(condition, message)
    raise InvariantError, message unless condition
  end

  def self.input!(condition, message)
    raise InvalidInputError, message unless condition
  end
end
