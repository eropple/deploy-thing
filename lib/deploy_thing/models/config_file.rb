module DeployThing
  module Models
    class ConfigFile < Sequel::Model(:config_files)
      REQUIRED_CONFIG_FILES = [ "iam.json", "launch.yaml", "userdata.bash" ].freeze

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
            when ".xml"

          end
        rescue
          errors.add(:content, "JSON or YAML failed to validate.")
        end
      end

      def self.latest(app, name)
        app_id = app.is_a?(Application) ? app.id : id.to_i
        where(:application_id => app_id, :name => name).reverse_order(:ordinal).first
      end

      def self.put(logger, app, config_name, content)
        latest_file = Models::ConfigFile.latest(app, config_name)

        if latest_file && latest_file.content.strip == content.strip
          logger.info "Content of upload is the same; skipping."
        else
          case File.extname(config_name)
            when ".json"
              logger.debug "Linting as JSON..."
              JSON.parse(content)
            when ".yaml", ".yml"
              logger.debug "Linting as YAML..."
              YAML.load(content)
            when ".xml"
              logger.debug "Linting as XML..."
              Nokogiri::XML(content) do |config|
                config.strict
              end
          end

          file = ConfigFile.new
          file.application_id = app.id
          file.ordinal = (latest_file != nil ? latest_file.ordinal : 0) + 1
          file.name = config_name
          file.content = content

          file.save
          logger.info "Uploaded '#{file.name}' as version \##{file.ordinal}."

          Config.with_new_file(app, file)
        end
      end
    end
  end
end