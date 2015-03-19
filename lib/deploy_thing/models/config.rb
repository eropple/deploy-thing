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

      def deployable?
        missing_files = ConfigFile::REQUIRED_CONFIG_FILES.reject do |f|
          files.find { |cf| cf.name == f || cf.name == (f + ".erb") } != nil
        end

        missing_files.length == 0
      end

      def self.with_new_file(app, file)
        latest_config = Config.latest(app)
        config = Config.new
        config.application_id = app.id
        config.ordinal = (latest_config != nil ? latest_config.ordinal : 0) + 1
        config.save
        if latest_config
          latest_config.files.select { |f| f.name != file.name }.each { |f| config.add_file(f) }
        end
        config.add_file(file)
        config.save

        LOGGER.info "Created configuration version \##{config.ordinal}."
        LOGGER.warn "This config is missing one of [ #{ConfigFile::REQUIRED_CONFIG_FILES.join(", ")} ] " + 
                      "or their ERB equivalents; this config cannot deploy." unless config.deployable?

        config
      end

      # Attempts to find a config file by the requested name _or_ by the name "X.erb",
      # such that "get_file_contents('foo.yaml')" will return 'foo.yaml.erb'. If the
      # returned file is an ERB template, it will be processed, with the contents of
      # `erb_template_args` used as arguments to the template.
      #
      # Storing 'foo.yaml' and 'foo.yaml.erb' will result in the ERB file taking
      # precedence.
      def get_file_contents(filename, erb_template_args = {})
        require 'erber/templater'

        file = files.find { |f| f.name == filename + ".erb" }
        if file
          Erber::Templater.new(file.content).render(erb_template_args)
        else
          file = files.find { |f| f.name == filename }
          if file
            file.content
          else
            require 'pry'
            binding.pry
            raise "No file '#{filename}' found for get_file_contents."
          end
        end
      end

      # Processes all {ConfigFile} objects related to this `Config` that are _not_
      # part of {ConfigFile#REQUIRED_CONFIG_FILES}. These files (which are assumed
      # to be application-specific) are processed, if they're ERB files, and returned
      # as a Hash of name => content.
      def get_contents_for_all_non_reserved_files(erb_template_args = {})
        require 'erber/templater'
        non_reserved_files = files.reject { |f| ConfigFile::REQUIRED_CONFIG_FILES.include?(f.name) ||
                                                ConfigFile::REQUIRED_CONFIG_FILES.include?(f.name + ".erb") }

        ret = {}
        non_reserved_files.select { |f| File.extname(f.name) != ".erb" }.each do |f|
          ret[f.name] = f.content
        end
        non_reserved_files.select { |f| File.extname(f.name) != ".erb" }.each do |f|
          ret[f.name.gsub(/\.erb$/, "")] = Erber::Templater.new(f.content).render(erb_template_args)
        end
        ret
      end
    end
  end
end