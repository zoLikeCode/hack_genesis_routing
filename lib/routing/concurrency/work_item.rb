# frozen_string_literal: true

module Routing
  module Concurrency
    WorkItem = Data.define(:operation, :context)
  end
end
