require 'deploy_thing/workflow/summary'

module DeployThing
  module Workflow
    class ConfigSummary < Summary
      attr_reader :files

      def initialize(id, time, files)
        @files = files
        
        super(id, time)
      end
    end
  end
end