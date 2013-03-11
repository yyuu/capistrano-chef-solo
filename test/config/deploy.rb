set :application, "capistrano-chef-solo"
set :repository,  "."
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options do
  run_locally("rm -f known_hosts")
  {:user_known_hosts_file => "known_hosts"}
end

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano-chef-solo"

namespace(:test_all) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }

  task(:test_setup) {
    find_and_execute_task("chef-solo:setup")
    find_and_execute_task("chef-solo:version")
  }

  task(:test_run_with_local_cookbooks) {
    set(:chef_solo_run_list, %w(recipe[foo] recipe[bar] recipe[baz]))
    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_repository, File.expand_path("..", File.dirname(__FILE__)))
    reset!(:chef_solo_cookbooks)
    find_and_execute_task("chef-solo")
  }

# task(:test_run_with_remote_cookbooks) {
#   set(:chef_solo_run_list, %w(recipe[foo] recipe[bar]))
#   set(:chef_solo_cookbooks_scm, :git)
#   set(:chef_solo_cookbooks_repository, "git://github.com/yyuu/capistrano-chef-solo")
#   set(:chef_solo_cookbooks_revision, "develop")
#   set(:chef_solo_cookbooks_subdir, "test/config/cookbooks")
#   reset!(:chef_solo_cookbooks)
#   find_and_execute_task("chef-solo")
# }

  task(:test_run_with_run_list) {
    set(:chef_solo_run_list, %w(recipe[foo] recipe[bar] recipe[baz]))
    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_repository, File.expand_path("..", File.dirname(__FILE__)))
    reset!(:chef_solo_cookbooks)
    chef_solo.run_list("recipe[foo]")
  }
}

# vim:set ft=ruby sw=2 ts=2 :
