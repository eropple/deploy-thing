module DeployThing
  module Models
    class Application < Sequel::Model(:applications)
      one_to_many :policies, :class => "DeployThing::Models::Policy"
      one_to_many :userdata, :class => "DeployThing::Models::Userdata"

      one_to_many :configs, :class => "DeployThing::Models::Config"
      one_to_many :config_files, :class => "DeployThing::Models::ConfigFile"

      one_to_many :deploys, :class => "DeployThing::Models::Deploy"
    end
  end
end