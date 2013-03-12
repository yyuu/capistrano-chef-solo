# -*- encoding: utf-8 -*-
require File.expand_path('../lib/capistrano-chef-solo/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Yamashita Yuu"]
  gem.email         = ["yamashita@geishatokyo.com"]
  gem.description   = %q{a capistrano recipe to invoke chef-solo.}
  gem.summary       = %q{a capistrano recipe to invoke chef-solo.}
  gem.homepage      = "https://github.com/yyuu/capistrano-chef-solo"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
# gem.name          = "capistrano-chef-solo"
  gem.name          = "yyuu-capistrano-chef-solo"
  gem.require_paths = ["lib"]
  gem.version       = Capistrano::ChefSolo::VERSION

  gem.add_dependency("capistrano")
  gem.add_dependency("capistrano-rbenv", "~> 1.0.0rc1")
  gem.add_development_dependency("net-scp", "~> 1.0.4")
  gem.add_development_dependency("net-ssh", "~> 2.2.2")
  gem.add_development_dependency("vagrant", "~> 1.0.6")
end
