require 'deploy_thing/models/ordinal_model_helpers'

module DeployThing
  module Models
    class Config < Sequel::Model(:configs)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      one_to_many :deploys, :class => "DeployThing::Models::Deploy",
                            :key => :config_id

      many_to_many :files,  :class => "DeployThing::Models::ConfigFile",
                            :left_key => :config_id,
                            :right_key => :config_file,
                            :join_table => :config_file_mapping
    end
  end
end