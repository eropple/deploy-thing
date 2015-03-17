module DeployThing
  module Models
    class LoadBalancer < Sequel::Model(:load_balancers)
      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id
    end
  end
end