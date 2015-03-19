# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'deploy_thing/version'

Gem::Specification.new do |spec|
  spec.name          = "deploy_thing"
  spec.version       = DeployThing::VERSION
  spec.authors       = ["Ed Ropple"]
  spec.email         = ["ed@edropple.com"]

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com' to prevent pushes to rubygems.org, or delete to allow pushes to any server."
  end

  spec.summary       = %q{TODO: Write a short summary, because Rubygems requires one.}
  spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.8"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'pry-rescue'
  spec.add_development_dependency 'pry-stack_explorer'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'guard-rspec'

  spec.add_runtime_dependency     "pry"
  spec.add_runtime_dependency     'cri',                '~> 2.6.1'
  spec.add_runtime_dependency     'erber',              '~> 0.1.1'
  spec.add_runtime_dependency     "hashie",             "~> 3.3"
  spec.add_runtime_dependency     'activesupport',      '~> 4.2.0'

  spec.add_runtime_dependency     'aws-sdk',            '~> 2.0.21.pre'
  spec.add_runtime_dependency     'aws-sdk-resources',  '~> 2.0.21.pre'

  spec.add_runtime_dependency     'sequel',             '~> 4.20.0'
  spec.add_runtime_dependency     'sqlite3',            '~> 1.3.10'

  spec.add_runtime_dependency     'table_print',        '~> 1.5.3'

  spec.add_runtime_dependency     'nokogiri',           '~> 1.6.6.2'
end
