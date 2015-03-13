require 'table_print'

module DeployThing
  module CLI
    module DSLExtensions
      def core_opts
        flag  :d,  :debug, "enable debug"
        flag  :h,  :help,  'show help for this command' do |value, cmd|
          puts cmd.help
          exit 0
        end
        flag  :v,  :verbose, "increase log verbosity" do |value, cmd|
          logger.level = Logger::DEBUG
        end
        flag  nil, :trace, "trace function calls" do |value, cmd|
          set_trace_func proc { |event, file, line, id, binding, classname|
            if event == 'call'
              puts "#{file}:#{line} #{classname}##{id}"
            end
          }
        end
      end
      def aws_opts
        optional nil, :iam,           "use instance profile credentials"
        optional nil, :profile,       "use specified profile from ~/.aws/credentials"
      end
      def db_opts
        required nil, :db,            "database connection string"
      end


      def credentials_from_opts(opts)
        require 'aws-sdk'

        raise "--iam or --profile must be used." unless (opts[:iam] ^ opts[:profile])

        if opts[:iam]
          Aws::InstanceProfileCredentials.new
        elsif opts[:profile]
          Aws::SharedCredentials.new(:profile_name => opts[:profile])
        else
          raise "???"
        end
      end
      def db_from_opts(opts)
        raise "--db is required." unless opts[:db]

        db = Sequel.connect(opts[:db])
        Sequel::Model.db = db
        db
      end
    end

    def self.main()
      require 'cri'
      require 'pry'
      require 'logger'

      logger = Logger.new($stderr)

      sub_commands = [pry_command, db_commands(logger),
                      application_commands(logger),
                      policy_commands(logger),
                      userdata_commands(logger),
                      config_commands(logger),
                      deploy_commands(logger),
                      launch_commands(logger),
                      lb_commands(logger)].flatten

      root = Cri::Command.define do
        extend DSLExtensions

        name        'deploy_thing'
        description 'the DeployThing deployment manager'

        core_opts

        run do |opts, args, cmd|
          logger.error "No subcommand given to `deploy_thing`."
          logger.error "Valid entries: #{sub_commands.map { |c| c.name }.join(', ')}"
        end
      end

      sub_commands.each { |cmd| root.add_command(cmd) }

      root.run(ARGV)
    end

    def self.pry_command
      Cri::Command.define do
        extend DSLExtensions 

        name        'pry'
        description 'opens a Pry debugger inside the context of the app'

        core_opts

        run do |opts, args, cmd|
          binding.pry
        end
      end
    end

    def self.db_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'db-test'
          description 'test database connectivity'

          db_opts

          run do |opts, args, cmd|
            begin
              db = db_from_opts(opts)
              db["SELECT 1"]
              logger.info "Connected to the database successfully."
            rescue StandardError => err
              logger.error "Failed to connect to database (#{err.class})."
              err.backtrace.each { |bt| logger.error bt }
              Kernel.exit(1)
            end
          end
        end,

        Cri::Command.define do
          extend DSLExtensions 
        
          name        'db-migrate'
          description 'migrate database'

          db_opts

          optional nil, :"migration-version", "database version (defaults to latest)"

          run do |opts, args, cmd|
            db = db_from_opts(opts)

            migration_path = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "migrations"))

            Sequel.extension :migration

            if opts[:"migration-version"]
              logger.info "Migrating to version #{opts[:"migration-version"]}."
              Sequel::Migrator.run(db, migration_path, target: opts[:"migration-version"].to_i, use_transactions: true)
            else
              logger.info "Migrating to latest."
              Sequel::Migrator.run(db, migration_path, use_transactions: true)
            end
          end
        end
      ]
    end

    def self.application_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'list-applications'
          description 'list all applications'

          db_opts

          run do |opts, args, cmd|
            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              tp(Models::Application.all.map do |app|
                { :id => app.id, :name => app.name }
              end)
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'create-application'
          description 'creates an application'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.new
              app.name = "test-app"
              app.save

              logger.info "Creating application '#{app.name}' (\##{app.id})"
            end
          end
        end
      ]
    end

    def self.policy_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'list-policies'
          description 'list policies for an application'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              tp(app.policies.sort { |a,b| a.ordinal <=> b.ordinal }.map do |p|
                {
                  :application => app.name,
                  :version => p.ordinal,
                  :time => p.created_at
                }
              end)
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'show-policy'
          description 'shows the requested policy'

          db_opts
          
          required :a, :"application-name", "application name"
          optional :p, :"policy-version",   "policy version"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app
              policy = 
                if opts[:"policy-version"]
                  Models::Policy.where( :application_id => app.id, :ordinal => opts[:"policy-version"].to_i )
                else
                  Models::Policy.latest(app)
                end

              raise "No policy found." unless policy
              puts policy.formatted_content
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'put-policy'
          description 'uploads a policy from a file'

          db_opts
          
          required :a, :"application-name", "application name"
          required :f, :"policy-file",      "local policy file"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]
            raise "--policy-file is required and must exist." \
              unless opts[:"policy-file"] && File.exist?(opts[:"policy-file"])

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              latest_policy = Models::Policy.latest(app)
              policy = Models::Policy.new
              policy.application_id = app.id
              policy.ordinal = (latest_policy != nil ? latest_policy.ordinal : 0) + 1

              policy.content = IO.read(opts[:"policy-file"])
              policy.save

              logger.info "Uploaded '#{opts[:"policy-file"]}' as policy \##{policy.ordinal}."
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'edit-policy'
          description 'interactively edits policy'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              latest_policy = Models::Policy.latest(app)
              body = latest_policy != nil ? latest_policy.formatted_content : ""
              new_body = Util::Files::edit_interactively(body).strip

              if (body == new_body)
                logger.info "No changes made; skipping upload."
              else
                policy = Models::Policy.new
                policy.application_id = app.id
                policy.ordinal = (latest_policy != nil ? latest_policy.ordinal : 0) + 1

                policy.content = new_body
                policy.save

                logger.info "Edited policy; new version \##{policy.ordinal}."
              end
            end
          end
        end
      ]
    end

    def self.userdata_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'list-userdata'
          description 'list userdata for an application'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app
              tp(app.userdata.sort { |a,b| a.ordinal <=> b.ordinal }.map do |p|
                {
                  :application => app.name,
                  :version => p.ordinal,
                  :time => p.created_at
                }
              end)
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'show-userdata'
          description 'shows the requested userdata'

          db_opts
          
          required :a, :"application-name", "application name"
          optional :p, :"userdata-version", "userdata version"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app
              userdata = 
                if opts[:"userdata-version"]
                  Models::Userdata.where( :application_id => app.id, :ordinal => opts[:"userdata-version"].to_i ).first
                else
                  Models::Userdata.latest(app)
                end

              raise "No userdata found." unless userdata
              puts userdata.content
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'put-userdata'
          description 'uploads a userdata from a file'

          db_opts
          
          required :a, :"application-name", "application name"
          required :f, :"userdata-file",    "local userdata file"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]
            raise "--userdata-file is required and must exist." \
              unless opts[:"userdata-file"] && File.exist?(opts[:"userdata-file"])

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              latest_userdata = Models::Userdata.latest(app)
              userdata = Models::Userdata.new
              userdata.application_id = app.id
              userdata.ordinal = (latest_userdata != nil ? latest_userdata.ordinal : 0) + 1

              userdata.content = IO.read(opts[:"userdata-file"])
              userdata.save

              logger.info "Uploaded '#{opts[:"userdata-file"]}' as userdata \##{userdata.ordinal}."
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'edit-userdata'
          description 'interactively edits userdata'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              latest_userdata = Models::Userdata.latest(app)
              body = latest_userdata != nil ? latest_userdata.content : ""
              new_body = Util::Files::edit_interactively(body).strip

              if JSON.parse(body) == JSON.parse(new_body)
                logger.info "No changes made; skipping upload."
              else
                userdata = Models::Userdata.new
                userdata.application_id = app.id
                userdata.ordinal = (latest_userdata != nil ? latest_userdata.ordinal : 0) + 1

                userdata.content = new_body
                userdata.save

                logger.info "Edited userdata; new version \##{userdata.ordinal}."
              end
            end
          end
        end
      ]
    end

    def self.config_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'list-configs'
          description 'list configs for an application'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app
              tp(app.configs.sort { |a, b| a.ordinal <=> b.ordinal }.map do |p|
                {
                  :application => app.name,
                  :version => p.ordinal,
                  :time => p.created_at
                }
              end)
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'list-config-files'
          description 'list files for a given config'

          db_opts
          
          required :a, :"application-name", "application name"
          optional :c, :"config-version", "version of the config to list"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              opts[:"config-version"] ||= Models::Config.latest(app).ordinal

              config =
                if opts[:"config-version"]
                  Models::Config.where( :application_id => app.id, :ordinal => opts[:"config-version"].to_i ).first
                else
                  Models::Config.latest(app)
                end

              tp(config.files.sort { |a, b| a.name <=> b.name}.map do |f|
                {
                  :application => app.name,
                  :config => config.id,
                  :filename => f.name,
                  :version => f.ordinal,
                  :time => f.created_at
                }
              end)
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'show-config-file'
          description 'shows a given config file'

          db_opts
          
          required :a, :"application-name", "application name"
          required :n, :"config-name", "name of the file to store"
          optional nil, :"config-version", "remote version"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]
            raise "--config-name is required." unless opts[:"config-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              config =
                if opts[:"config-version"]
                  Models::Config.where( :application_id => app.id, :ordinal => opts[:"config-version"].to_i ).first
                else
                  Models::Config.latest(app)
                end
              raise "Couldn't find configuration for app (has one been created?)." unless config

              file = config.files.find { |f| f.name == opts[:"config-name"] }
              raise "Couldn't find file '#{opts[:"config-name"]}'." unless file

              puts file.content
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'put-config-file'
          description 'upload a new config file'

          db_opts
          
          required :a, :"application-name", "application name"
          required :n, :"config-name", "name of the file to store"
          required nil, :"config-file", "local file to push"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]
            raise "--config-name is required." unless opts[:"config-name"]
            raise "--config-file is required and must exist." \
              unless opts[:"config-file"] && File.exist?(opts[:"config-file"])

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              latest_file = Models::ConfigFile.latest(app, opts[:"config-name"])

              file = Models::ConfigFile.new
              file.application_id = app.id
              file.ordinal = (latest_file != nil ? latest_file.ordinal : 0) + 1
              file.name = opts[:"config-name"]
              file.content = IO.read(opts[:"config-file"])

              file.save
              logger.info "Uploaded '#{file.name}' as version \##{file.ordinal}."

              latest_config = Models::Config.latest(app)
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
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'edit-config-file'
          description 'interactively edit a config file'

          db_opts
          
          required :a, :"application-name", "application name"
          required :n, :"config-name", "name of the file to store"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]
            raise "--config-name is required." unless opts[:"config-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              latest_file = Models::ConfigFile.latest(app, opts[:"config-name"])
              body = latest_file != nil ? latest_file.content : ""
              new_body = DeployThing::Util::Files::edit_interactively(body, File.extname(opts[:"config-name"]))

              if (body.strip == new_body.strip)
                logger.info "No changes made to file; skipping."
              else
                file = Models::ConfigFile.new
                file.application_id = app.id
                file.ordinal = (latest_file != nil ? latest_file.ordinal : 0) + 1
                file.name = opts[:"config-name"]
                file.content = new_body

                file.save
                logger.info "Edited '#{file.name}' into version \##{file.ordinal}."

                latest_config = Models::Config.latest(app)
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
              end
            end
          end
        end
      ]
    end

    def self.deploy_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'list-deploys'
          description 'list deploys for an application'

          db_opts
          
          required :a, :"application-name", "application name"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app
              tp(app.deploys.sort { |a, b| a.ordinal <=> b.ordinal }.map do |p|
                {
                  :application => app.name,
                  :version => p.ordinal,
                  :time => p.created_at,
                  :artifact => p.artifact_version,
                  :userdata => p.userdata.ordinal,
                  :policy => p.policy.ordinal,
                  :config => p.config.ordinal
                }
              end)
            end
          end
        end,
        Cri::Command.define do
          extend DSLExtensions 
        
          name        'create-deploy'
          description 'creates a new deploy for an application'

          db_opts
          
          required :a, :"application-name", "application name"
          required :r, :"artifact-version", "version of the artifact to bind"
          optional :c, :"config-version", "version of the config to bind"
          optional :p, :"policy-version", "version of the policy to bind"
          optional :u, :"userdata-version", "version of the userdata to bind"

          run do |opts, args, cmd|
            raise "--application-name is required." unless opts[:"application-name"]
            raise "--artifact-version is required." unless opts[:"artifact-version"]

            db = db_from_opts(opts)
            require 'deploy_thing/models'

            db.transaction do
              app = Models::Application.where( :name => opts[:"application-name"] ).first
              raise "Unknown application '#{opts[:"application-name"]}'." unless app

              config =
                if opts[:"config-version"]
                  Models::Config.where( :application_id => app.id, :ordinal => opts[:"config-version"].to_i ).first
                else
                  Models::Config.latest(app)
                end
              policy = 
                if opts[:"policy-version"]
                  Models::Policy.where( :application_id => app.id, :ordinal => opts[:"policy-version"].to_i )
                else
                  Models::Policy.latest(app)
                end
              userdata = 
                if opts[:"userdata-version"]
                  Models::Userdata.where( :application_id => app.id, :ordinal => opts[:"userdata-version"].to_i ).first
                else
                  Models::Userdata.latest(app)
                end

              latest_deploy = Models::Deploy.latest(app)

              if latest_deploy &&
                 latest_deploy.artifact_version == opts[:"artifact-version"] &&
                 latest_deploy.config_id == config.id &&
                 latest_deploy.policy_id == policy.id &&
                 latest_deploy.userdata_id == userdata.id

                 logger.info "The requested deploy is the same as the current latest deploy; doing nothing."

              else
                deploy = Models::Deploy.new
                deploy.application_id = app.id
                deploy.ordinal = (latest_deploy != nil ? latest_deploy.ordinal : 0) + 1
                deploy.artifact_version = opts[:"artifact-version"]
                deploy.config = config
                deploy.policy = policy
                deploy.userdata = userdata

                deploy.save
                logger.info "New deploy saved as \##{deploy.ordinal}."
              end
            end
          end
        end
      ]
    end

    def self.launch_commands(logger)
      []
    end

    def self.lb_commands(logger)
      []
    end
  end
end