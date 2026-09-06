# frozen_string_literal: true

module Routing
  module Execution
    class Executor
      def try_submit
        raise NotImplementedError, "#{self.class}#try_submit"
      end

      def submit
        raise NotImplementedError, "#{self.class}#submit"
      end

      def shutdown
        raise NotImplementedError, "#{self.class}#shutdown"
      end
    end
  end
end
