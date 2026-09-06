# frozen_string_literal: true

require "json"
require "fileutils"

module Routing
  module JsonFile
    def self.read(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError, Errno::ENOENT => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end

    def self.write(path, data)
      temporary = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
      File.write(temporary, "#{JSON.pretty_generate(data)}\n")
      FileUtils.mv(temporary, path, force: true)
    rescue Errno::ENOENT, Errno::EACCES, Errno::EROFS => e
      raise InvalidInputError, "#{path}: #{e.message}"
    ensure
      File.delete(temporary) if defined?(temporary) && File.exist?(temporary)
    end
  end
end
