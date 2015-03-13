module DeployThing
  module Models
    module OrdinalModelHelpers
      def latest(app)
        app_id = app.is_a?(Application) ? app.id : id.to_i
        where(:application_id => app_id).reverse_order(:ordinal).first
      end
    end
  end
end