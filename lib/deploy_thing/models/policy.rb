require 'json'

module DeployThing
  module Models
    class Policy < Sequel::Model(:policies)
      self.extend OrdinalModelHelpers

      plugin :validation_helpers
      plugin :timestamps

      many_to_one :application, :class => "DeployThing::Models::Application",
                                :key => :application_id

      def formatted_content
        JSON.pretty_generate(JSON.parse(self.content))
      end

      def validate
        super
        validates_presence [ :content ]
        begin
          JSON.parse(self.content)
        rescue
          errors.add(:content, "must be valid JSON")
        end
      end

      def before_save
        self.content = JSON.parse(self.content).to_json
        super
      end
    end
  end
end