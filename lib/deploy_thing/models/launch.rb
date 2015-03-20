module DeployThing
  module Models
    class Launch < Sequel::Model(:launches)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      many_to_one :deploy,  :class => "DeployThing::Models::Deploy",
                            :key => :deploy_id
    
      def self.create(env, deploy)
        app = deploy.application

        last_launch = Launch::latest(app)

        launch = Launch.new
        launch.application_id = app.id
        launch.deploy_id = deploy.id
        launch.ordinal = (last_launch ? last_launch.ordinal : 0) + 1
        launch.status = LaunchStatus::NOT_CREATED

        LOGGER.info "Preparing launch \##{launch.ordinal}."
        launch.save(raise_on_failure: true)

        launch.up!(env)
      end

      def up!(env)
        raise "Cannot re-launch a launch. Create a new one." unless status == LaunchStatus::NOT_CREATED

        begin
          ld = deploy.get_launch_details

          deploy.ensure_prerequisites(env)
          asg_client = Aws::AutoScaling::Client.new(region: ld[:region], credentials: env.aws_credentials)

          lc_name = deploy.get_launch_configuration_name
          self.aws_id = "#{application.name}-Launch_#{ordinal}"

          asg_max = (ld[:asg][:size] || {})[:max] || 1
          asg_min = (ld[:asg][:size] || {})[:min] || asg_min

          LOGGER.debug "Creating auto scaling group '#{aws_id}' with launch configuration '#{lc_name}'..."
          resp = asg_client.create_auto_scaling_group(
            auto_scaling_group_name: aws_id,

            launch_configuration_name: lc_name,
            min_size: asg_min,
            max_size: asg_max,
            desired_capacity: asg_max,
            default_cooldown: ld[:asg][:cooldown],

            vpc_zone_identifier: ld[:asg][:subnets].join(","),

            tags: {}.merge(ld[:asg][:tags] || {})
          )

          LOGGER.info "Launch \##{ordinal} (ASG name '#{aws_id}') succeeded."
          self.status = LaunchStatus::UP
          save_changes
            
        rescue Exception => e
          LOGGER.error "Launch \##{ordinal} (ASG name '#{aws_id}') failed."
          self.status = LaunchStatus::FAILED
          save_changes

          raise e
        end

        self
      end

      def down!(env)
        raise "Cannot down a launch that is not currently up." unless status == LaunchStatus::UP

        ld = deploy.get_launch_details
        asg_client = Aws::AutoScaling::Client.new(region: ld[:region], credentials: env.aws_credentials)

        begin
          resp = asg_client.describe_auto_scaling_groups(
            auto_scaling_group_names: [ aws_id ],
            max_records: 1
          )

          if resp[:auto_scaling_groups].empty?
            LOGGER.info "Auto-scaling group for launch \##{ordinal} doesn't exist, looks already cleaned up."
          else
            LOGGER.info "Resizing auto-scaling group to zero and waiting for instances to go down..."
            asg_client.update_auto_scaling_group(
              auto_scaling_group_name: aws_id,
              min_size: 0,
              max_size: 0,
              desired_capacity: 0
            )

            loop do
              resp = asg_client.describe_auto_scaling_groups(
                auto_scaling_group_names: [ aws_id ],
                max_records: 1
              )

              if resp[:auto_scaling_groups].empty?
                LOGGER.debug "ASG not found; assuming manual cleanup."
                break
              end

              break if resp[:auto_scaling_groups][0][:instances].empty?
              LOGGER.info "Waiting on instances..."
              sleep 5
            end

            LOGGER.info "Auto-scaling group is empty. Deleting..."
            asg_client.delete_auto_scaling_group(
              auto_scaling_group_name: aws_id
            )
            LOGGER.info "Deleted ASG '#{aws_id}'."
          end

          self.status = LaunchStatus::DOWN
          save_changes
        rescue StandardError => e
          LOGGER.error "Down of launch \##{ordinal} failed. Not setting to DOWN; should be safe to re-run."
          raise e
        end

        deploy.destroy_prerequisites_if_childless(env)
      end
    end
    module LaunchStatus
      NOT_CREATED = 0
      UP = 1
      DOWN = 2
      FAILED = 666
    end
  end
end