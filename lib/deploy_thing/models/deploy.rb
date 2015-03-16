module DeployThing
  module Models
    class Deploy < Sequel::Model(:deploys)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      many_to_one :config,  :class => "DeployThing::Models::Config",
                            :key => :config_id
    end
  end
end