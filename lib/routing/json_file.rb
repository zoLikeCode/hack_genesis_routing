# frozen_string_literal: true

require "json"

module Routing
  module JsonFile
    def self.read(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError, Errno::ENOENT => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end

    def self.write(path, data)
      File.write(path, "#{JSON.pretty_generate(data)}\n")
    rescue Errno::ENOENT, Errno::EACCES, Errno::EROFS => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end
  end
end
