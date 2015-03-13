module DeployThing
  module Models
    class Userdata < Sequel::Model(:userdata)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      one_to_many :deploys, :class => "DeployThing::Models::Deploy",
                            :key => :userdata_id

      def validate
        super
        validates_presence [ :content ]
      end
    end
  end
end