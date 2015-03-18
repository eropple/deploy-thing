module DeployThing
  module Models
    class Launch < Sequel::Model(:launches)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      many_to_one :deploy,  :class => "DeployThing::Models::Deploy",
                            :key => :deploy_id
    
      def self.launch(app, config)

        
      end
    end
  end
end