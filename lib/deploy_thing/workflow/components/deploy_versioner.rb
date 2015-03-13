module DeployThing
  module Workflow
    module Components
      class DeployVersioner


        def initialize(application, logger, s3_bucket)
          @application = application
          @deploys = SimpleVersioner.new(logger, @application.name, "deploy", s3_bucket, "deploys")
        end

        def summaries

        end

        def info(id)
        end

        def build(artifact_id, policy_id, userdata_id, config_id)
        end
      end
    end
  end
end