require 'deploy_thing/workflow/application'

module DeployThing
  module CLI
    module DSLExtensions
      def core_opts
        optional nil, :iam,           "use instance profile credentials"
        optional nil, :profile,       "use specified profile from ~/.aws/credentials"
        required nil, :db,            "database connection string"
        required nil, :region,        "AWS region"

        required nil, :"application-name", "name of the application in question"
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

      def s3_from_opts(opts)
        creds = credentials_from_opts(opts)

        client = Aws::S3::Client.new(region: opts[:region], credentials: creds)
        resource_client = Aws::S3::Resource.new(client: client)

        bucket = resource_client.bucket(opts[:bucket])
        raise "no bucket found for '#{opts[:bucket]}'." unless bucket

        bucket
      end
    end

    def self.main()
      require 'cri'
      require 'pry'
      require 'logger'

      logger = Logger.new($stderr)

      sub_commands = [pry_command, policy_commands(logger),
                      config_commands(logger), userdata_commands(logger)].flatten

      root = Cri::Command.define do
        name        'deploy_thing'
        description 'the DeployThing deployment manager'

        flag  nil, :"no-color", "disable colorized output"
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

        flag nil, :iam, "use IAM role as credential store"

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
        name        'pry'
        description 'opens a Pry debugger inside the context of the app'

        run do |opts, args, cmd|
          binding.pry
        end
      end
    end

    def self.policy_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions

          name        'edit-policy'
          description 'edits a policy for the requested application'

          core_opts

          required nil, :name, "application name"

          run do |opts, args, cmd|
            s3 = s3_from_opts(opts)

            Workflow::Application.new(logger, s3, opts[:name]).policies.edit
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'upload-policy'
          description 'uploads a policy for the requested application'

          core_opts

          required nil, :name, "application name"
          required nil, :"policy-file", "policy file to upload"

          run do |opts, args, cmd|
            raise "'#{opts[:"policy-file"]}' does not exist." unless File.exist?(opts[:"policy-file"])

            s3 = s3_from_opts(opts)

            Workflow::Application.new(logger, s3, opts[:name]).policies.put(IO.read(opts[:"policy-file"]))
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'list-policies'
          description 'lists all policies for the requested application'

          core_opts

          required nil, :name, "application name"

          run do |opts, args, cmd|
            require 'table_print'

            s3 = s3_from_opts(opts)

            retval = Workflow::Application.new(logger, s3, opts[:name]).policies.summaries

            puts "POLICIES:"
            tp retval
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'show-policy'
          description 'prints the requested policy'

          core_opts

          required nil, :name, "application name"
          optional nil, :id, "policy ID (defaults to head)"

          run do |opts, args, cmd|
            require 'table_print'

            s3 = s3_from_opts(opts)

            app = Workflow::Application.new(logger, s3, opts[:name])
            opts[:id] = (opts[:id] || app.head_policy_id).to_i

            policy = app.policies.read(opts[:id])
            raise "policy '#{opts[:id]}' does not exist." unless policy
            puts policy
          end
        end
      ]
    end

    def self.userdata_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions

          name        'edit-userdata'
          description 'edits userdata for the requested application'

          core_opts

          required nil, :name, "application name"

          run do |opts, args, cmd|
            s3 = s3_from_opts(opts)

            Workflow::Application.new(logger, s3, opts[:name]).userdata.edit
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'upload-userdata'
          description 'uploads userdata for the requested application'

          core_opts

          required nil, :name, "application name"
          required nil, :"userdata-file", "policy file to upload"

          run do |opts, args, cmd|
            raise "'#{opts[:"userdata-file"]}' does not exist." unless File.exist?(opts[:"userdata-file"])

            s3 = s3_from_opts(opts)

            Workflow::Application.new(logger, s3, opts[:name]).userdata.put(IO.read(opts[:"userdata-file"]))
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'list-userdata'
          description 'lists all userdata for the requested application'

          core_opts

          required nil, :name, "application name"

          run do |opts, args, cmd|
            require 'table_print'

            s3 = s3_from_opts(opts)

            retval = Workflow::Application.new(logger, s3, opts[:name]).userdata.summaries

            puts "USERDATA:"
            tp retval
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'show-userdata'
          description 'prints the requested userdata'

          core_opts

          required nil, :name, "application name"
          optional nil, :id, "userdata ID (defaults to head)"

          run do |opts, args, cmd|
            s3 = s3_from_opts(opts)

            app = Workflow::Application.new(logger, s3, opts[:name])
            opts[:id] = (opts[:id] || app.userdata.head_id).to_i

            puts app.userdata.read(opts[:id])
          end
        end
      ]
    end

    def self.config_commands(logger)
      [
        Cri::Command.define do
          extend DSLExtensions

          name        'list-configs'
          description 'lists all configs for the requested application'

          core_opts

          required nil, :name, "application name"

          run do |opts, args, cmd|
            require 'table_print'

            s3 = s3_from_opts(opts)

            retval = Workflow::Application.new(logger, s3, opts[:name]).config_summaries

            puts "CONFIGS:"
            tp retval
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'list-config-files'
          description 'lists all config files for the requested config'

          core_opts

          required nil, :name, "application name"
          optional nil, :id, "config ID (defaults to head)"

          run do |opts, args, cmd|
            require 'table_print'

            s3 = s3_from_opts(opts)

            app = Workflow::Application.new(logger, s3, opts[:name])

            opts[:id] = (opts[:id] || app.head_config_id).to_i

            puts "CONFIG FILES FOR ID #{opts[:id]}:"
            tp app.config_files(opts[:id])
          end
        end,
        Cri::Command.define do
          extend DSLExtensions

          name        'edit-config'
          description 'edits a given configuration file'

          core_opts

          required nil, :name, "application name"
          required nil, :file, "config file name"

          run do |opts, args, cmd|
            raise "required: --file" unless opts[:file]

            s3 = s3_from_opts(opts)
            app = Workflow::Application.new(logger, s3, opts[:name])
            app.edit_config(opts[:file])
          end
        end
      ]
    end
  end
end