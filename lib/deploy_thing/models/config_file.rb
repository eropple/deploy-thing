module DeployThing
  module Models
    class ConfigFile < Sequel::Model(:config_files)
      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      many_to_many :configs,  :class => "DeployThing::Models::Config",
                              :left_key => :config_file,
                              :right_key => :config_id,
                              :join_table => :config_file_mapping

      def validate
        super
        validates_presence [ :content ]
        begin
          case File.extname(self.name)
            when ".json"
              JSON.parse(self.content)
            when ".yaml", ".yml"
              YAML.load(self.content)
          end
        rescue
          errors.add(:content, "JSON or YAML failed to validate.")
        end
      end

      def self.latest(app, name)
        app_id = app.is_a?(Application) ? app.id : id.to_i
        where(:application_id => app_id, :name => name).reverse_order(:ordinal).first
      end
    end
  end
end