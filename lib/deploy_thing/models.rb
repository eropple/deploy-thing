require 'sequel'

Dir[File.expand_path(File.join(File.dirname(__FILE__), "models")) + "/*.rb"].each do |f|
  require_relative(f)
end