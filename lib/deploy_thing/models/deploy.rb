module DeployThing
  module Models
    class Deploy < Sequel::Model(:deploys)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      many_to_one :config,  :class => "DeployThing::Models::Config",
                            :key => :config_id

      one_to_many :launches, :class => "DeployThing::Models::Launch"

      def validate
        super
        errors.add(:config, "This config is not deployable.") unless config.deployable?
      end

      def get_launch_details
        Hashie::Mash.new(YAML.load(config.get_file_contents("launch.yaml", {})))
      end
      def get_s3_config_object(env)
        env.s3_bucket.object("configs/#{application.name}/#{config.ordinal}.tar.gz")
      end
      def get_launch_configuration_name
        "#{application.name}-Deploy_#{ordinal}"
      end

      def ensure_prerequisites(env)
        ld = get_launch_details

        LOGGER.info "Ensuring prerequisites for deploy \##{ordinal}."

        LOGGER.info "- S3 config package"
        s3_object = ensure_s3_configuration(env, ld)
        LOGGER.info "- IAM role"
        iam_role = ensure_iam_role(env, ld)
        LOGGER.info "- launch configuration"
        lc = ensure_aws_launch_configuration(env, ld, s3_object)
      end
      
      def destroy_prerequisites_if_childless(env)
        destroy(env) unless launches.length > 0
      end

      private
      def destroy(env)
        ld = get_launch_details
        LOGGER.info "Destroying prerequisites for deploy \##{ordinal}."

        LOGGER.info "- launch configuration"
        destroy_aws_launch_configuration(env)
        LOGGER.info "- IAM role"
        destroy_iam_role(env)
        LOGGER.info "- S3 config package"
        destroy_s3_configuration(env, ld)
      end

      def ensure_s3_configuration(env, ld)
        s3_object = get_s3_config_object(env)

        if !s3_object.exist?
          archive = Dir.mktmpdir do |dir|
            config.get_contents_for_all_non_reserved_files(ld[:custom_args] || {}).each_pair do |name, content|
              IO.write("#{dir}/#{name}", content)
            end

            DeployThing::Util::Tar.new.tar(dir)
          end

          LOGGER.debug "Uploading archive to 's3://#{s3_object.bucket.name}/#{s3_object.key}' ..."
          s3_object.put(:body => archive)
          LOGGER.debug "Upload done."
        end

        s3_object
      end

      def destroy_s3_configuraton(env)
        s3_object = get_s3_config_object(env)

        s3_object.delete unless !s3_object.exist?
      end

      def iam_role_name(env)
        # TODO: consider changing this to use the iam.json file ordinal; that might be confusing.
        "#{application.name}-Config_#{config.ordinal}"
      end
      def ensure_iam_role(env, ld)
        iam_client = Aws::IAM::Client.new(region: ld[:region], credentials: env.aws_credentials)
        iam_resource = Aws::IAM::Resource.new(client: iam_client)

        role_name = iam_role_name(env)

        LOGGER.debug "Attempting to find role '#{role_name}'..."
        
        begin
          role = iam_resource.role(role_name)
          role.role_id

          LOGGER.debug "Found '#{role_name}', returning it."
          role
        rescue Aws::IAM::Errors::NoSuchEntity => e
          LOGGER.debug "No role '#{role_name}', must create."
          s3_config = get_s3_config_object(env)
          iam_args = {
            :application_name => application.name,
            :s3_bucket => s3_config.bucket.name
          }
          iam_policy = config.get_file_contents("iam.json", iam_args)

          role = iam_resource.create_role(
            :assume_role_policy_document => assume_role_policy_document,
            :role_name => role_name
          )
          LOGGER.debug "Created '#{role_name}', attaching policies."
          policy = Aws::IAM::RolePolicy.new(role_name: role_name,
                                            name: "DeployThing-#{config.ordinal}",
                                            client: iam_client)
          policy.put(policy_document: iam_policy)
          LOGGER.debug "Uploaded policy to '#{role_name}' (#{iam_policy.length} characters)."

          role
        end
      end
      def destroy_iam_role(env)
        iam_client = Aws::IAM::Client.new(region: ld[:region], credentials: env.aws_credentials)
        iam_resource = Aws::IAM::Resource.new(client: iam_client)

        role_name = iam_role_name(env)

        LOGGER.debug "Attempting to find role '#{role_name}'..."
        role = iam_resource.role(role_name)
        if role
          LOGGER.debug "Found '#{role_name}', destroying it."
          role.delete
        end
      end

      def build_userdata(env)
        require 'base64'
        require 'erber/templater'

        s3_config = get_s3_config_object(env)
        userdata_args = {
          :application_name => application.name,
          :artifact_version => artifact_version,
          :s3_bucket => s3_config.bucket.name,
          :s3_key => s3_config.key
        }
        
        Base64::encode64(config.get_file_contents("userdata.bash", userdata_args))
      end
      
      def iam_role_name(env)
        "#{application.name}-Deploy_#{ordinal}"
      end
      def iam_profile_name(env)
        iam_role_name(env)
      end
      def ensure_aws_launch_configuration(env, ld, s3_object)
        asg_client = Aws::AutoScaling::Client.new(region: ld[:region], credentials: env.aws_credentials)
        iam_client = Aws::IAM::Client.new(region: ld[:region], credentials: env.aws_credentials)

        lc_name = get_launch_configuration_name
        LOGGER.debug "Checking for launch configuration '#{lc_name}'..."
        lc = asg_client.describe_launch_configurations(launch_configuration_names: [ lc_name ])[:launch_configurations][0]
        if !lc
          LOGGER.debug "Launch configuration '#{lc_name}' not found, creating."
          userdata = build_userdata(env)

          require 'pry'; binding.pry
          profile_name = iam_profile_name(env)
          iam_client.create_instance_profile(instance_profile_name: profile_name)
          iam_client.add_role_to_instance_profile(
            instance_profile_name: profile_name,
            role_name: iam_role_name(env)
          )
          require 'pry'; binding.pry

          begin
            lc = asg_client.create_launch_configuration(
              launch_configuration_name: lc_name,
              image_id: ld[:asg][:ami],
              key_name: ld[:asg][:ssh_key_pair],
              security_groups: ld[:asg][:security_groups],

              instance_type: ld[:asg][:"instance-type"],
              ebs_optimized: ld[:asg][:"ebs-optimized"] || false,
              instance_monitoring: {
                :enabled => ld[:asg][:"detailed-monitoring"] || false
              },
              associate_public_ip_address: ld[:asg][:"public-ip"] || false,

              iam_instance_profile: profile_name,

              user_data: build_userdata(env)
            )
          rescue StandardError => e
            delete_instance_profile(env, iam_client)
            raise e
          end
        end

        lc
      end

      def delete_instance_profile(env, iam_client)
        iam_client.remove_role_from_instance_profile(
          instance_profile_name: iam_profile_name(env),
          role_name: iam_role_name(env)
        )
        iam_client.delete_instance_profile(
          instance_profile_name: iam_profile_name(env)
        )
      end

      def destroy_aws_launch_configuration(env, ld)
        asg_client = Aws::AutoScaling::Client.new(region: ld[:region], credentials: env.aws_credentials)
        iam_client = Aws::IAM::Client.new(region: ld[:region], credentials: env.aws_credentials)

        lc_name = get_launch_configuration_name
        LOGGER.debug "Checking for launch configuration '#{lc_name}'..."
        lc = asg_client.describe_launch_configuration(launch_configuration_names: [ lc_name ])[:launch_configurations][0]

        if lc
          LOGGER.debug "Found launch configuration '#{lc_name}', deleting."
          asg_client.delete_launch_configuration(launch_configuration_name: lc_name)

          delete_instance_profile(iam_client)
        end
      end

      def assume_role_policy_document
        {
            "Version" => "2012-10-17",
            "Statement" => [{
                "Effect" => "Allow",
                "Principal" => {
                    "Service" => ["ec2.amazonaws.com"]
                },
                "Action" => ["sts:AssumeRole"],
            }]
        }.to_json
      end
    end
  end
end