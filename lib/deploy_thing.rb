require "deploy_thing/version"

require "aws-sdk"

Dir[File.expand_path "lib/deploy_thing/**/*.rb"].each do |f|
  require_relative(f)
end