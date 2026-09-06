# frozen_string_literal: true

module Routing
  module Concurrency
    class DispatchSlots
      def initialize(providers:, policy:, executor_class:, reactor_task:)
        Routing.assert(providers.respond_to?(:each), "dispatch slots require providers")
        Routing.assert(policy.is_a?(Policy), "dispatch slots require Policy")
        @pools = {}
        providers.each do |provider|
          @pools[provider.name] = executor_class.new(
            limit: limit_for(provider, policy),
            reactor_task: reactor_task
          )
        end
      end

      def try_submit(name)
        pool_for(name).try_submit
      end

      def submit(name, &)
        pool_for(name).submit(&)
      end

      def any_available?(names)
        names.any? { |name| @pools.key?(name) && try_submit(name) }
      end

      def shutdown
        @pools.each_value(&:shutdown)
        self
      end

      private

      def pool_for(name)
        pool = @pools[name]
        Routing.assert(!pool.nil?, "unknown dispatch pool #{name}")
        pool
      end

      def limit_for(provider, policy)
        configured = policy.concurrency.fetch("max_workers_per_provider")
        native = provider.in_progress_count_limit || policy.concurrency.fetch("fallback_worker_limit")
        configured.nil? ? native : [native, configured].min
      end
    end
  end
end
