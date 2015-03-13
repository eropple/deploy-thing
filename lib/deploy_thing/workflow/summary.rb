module DeployThing
  module Workflow
    class Summary
      attr_reader :id
      attr_reader :time

      def initialize(id, time)
        raise "time must be of type Time." unless time.is_a?(Time)

        @id = id.to_i
        @time = time
      end
    end
  end
end