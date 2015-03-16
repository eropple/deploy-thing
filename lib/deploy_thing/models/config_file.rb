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

          iam_file = ConfigFile.latest(app, "iam.json")
          userdata_file = ConfigFile.latest(app, "userdata.bash")
          deploy_file = ConfigFile.latest(app, "deploy.yaml")

          if !(iam_file && userdata_file && deploy_file)
            logger.info "Since iam.json, userdata.bash, and deploy.yaml don't exist, not creating a config."
            nil
          else
            latest_config = Config.latest(app)
            config = Models::Config.new
            config.application_id = app.id
            config.ordinal = (latest_config != nil ? latest_config.ordinal : 0) + 1
            config.save
            if latest_config
              latest_config.files.select { |f| f.name != file.name }.each { |f| config.add_file(f) }
            end
            config.add_file(file)
            config.save

            logger.info "Created configuration version \##{config.ordinal}."

            config
          end
        end
      end
    end
  end
end