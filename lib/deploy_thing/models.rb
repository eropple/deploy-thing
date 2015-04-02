require 'sequel'

Sequel::Model.raise_on_save_failure = true

Dir[File.expand_path(File.join(File.dirname(__FILE__), "models")) + "/*.rb"].each do |f|
  require_relative(f)
end