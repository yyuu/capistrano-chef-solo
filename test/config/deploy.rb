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
require "json"
require "tempfile"

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_with_local_cookbooks")
  find_and_execute_task("test_with_remote_cookbooks")
  find_and_execute_task("test_with_multiple_cookbooks")
}

def download_attributes()
  tempfile = Tempfile.new("attributes")
  download(chef_solo_attributes_file, tempfile.path)
  JSON.load(tempfile.read)
end

def assert_attributes(expected)
  found = download_attributes
  expected.each do |key, value|
    if found[key] != value
      abort("invalid attribute: #{key.inspect} (expected:#{value.inspect} != found:#{found[key].inspect})")
    end
  end
end

def assert_run_list(expected)
  found = download_attributes["run_list"]
  abort("invalid run_list (expected:#{expected.inspect} != found:#{found.inspect})") if found != expected
end

def check_applied_recipes!(expected)
  files = expected.map { |recipe| /^recipe\[(\w+)\]$/ =~ recipe; File.join("/tmp", $1) }
  begin
    files.each do |file|
      run("test -f #{file.dump}")
    end
  ensure
    sudo("rm -f #{files.map { |x| x.dump }.join(" ")}") rescue nil
  end
end

def flush_attributes!()
  set(:chef_solo_attributes, {})
  set(:chef_solo_role_attributes, {})
  set(:chef_solo_host_attributes, {})
  set(:chef_solo_run_list, [])
  set(:chef_solo_role_run_list, {})
  set(:chef_solo_host_run_list, {})
end

namespace(:test_default) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_default", "test_default:setup"
  after "test_default", "test_default:teardown"

  task(:setup) {
    flush_attributes!
    set(:chef_solo_attributes, {"aaa" => "AAA"})
    set(:chef_solo_role_attributes, {:app => {"bbb" => "BBB"}})
    set(:chef_solo_host_attributes, {"192.168.33.10" => {"ccc" => "CCC"}})
    set(:chef_solo_run_list, %w(recipe[foo]))
    set(:chef_solo_role_run_list, {:app => %w(recipe[bar])})
    set(:chef_solo_host_run_list, {"192.168.33.10" => %w(recipe[baz])})
  }

  task(:teardown) {
  }

  task(:test_setup) {
    find_and_execute_task("chef-solo:setup")
  }

  task(:test_version) {
    find_and_execute_task("chef-solo:version")
  }

  task(:test_attributes, :roles => :app) {
    chef_solo.update_attributes
    assert_attributes({"aaa" => "AAA", "bbb" => "BBB", "ccc" => "CCC", "run_list" => %w(recipe[foo] recipe[bar] recipe[baz])})
  }
}

namespace(:test_with_local_cookbooks) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_local_cookbooks", "test_with_local_cookbooks:setup"
  after "test_with_local_cookbooks", "test_with_local_cookbooks:teardown"

  task(:setup) {
    flush_attributes!
    set(:chef_solo_run_list, %w(recipe[foo] recipe[bar]))
    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_repository, File.expand_path("..", File.dirname(__FILE__)))
    set(:chef_solo_cookbooks_subdir, "config/cookbooks")
    reset!(:chef_solo_cookbooks)
  }

  task(:teardown) {
  }

  task(:test_invoke) {
    expected = chef_solo_run_list
    find_and_execute_task("chef-solo")
    assert_run_list(expected)
    check_applied_recipes!(expected)
  }

  task(:test_run_list) {
    expected = %w(recipe[baz])
    chef_solo.run_list expected
    assert_run_list(expected)
    check_applied_recipes!(expected)
  }
}

namespace(:test_with_remote_cookbooks) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_remote_cookbooks", "test_with_remote_cookbooks:setup"
  after "test_with_remote_cookbooks", "test_with_remote_cookbooks:teardown"

  task(:setup) {
    flush_attributes!
    set(:chef_solo_run_list, %w(recipe[one] recipe[two]))
    set(:chef_solo_cookbooks_scm, :git)
    set(:chef_solo_cookbooks_repository, "git://github.com/yyuu/capistrano-chef-solo")
    set(:chef_solo_cookbooks_revision, "develop")
    set(:chef_solo_cookbooks_subdir, "test/config/cookbooks2")
    reset!(:chef_solo_cookbooks)
  }

  task(:teardown) {
  }

# task(:test_invoke) {
#   expected = chef_solo_run_list
#   find_and_execute_task("chef-solo")
#   assert_run_list(expected)
#   check_applied_recipes!(expected)
# }

# task(:test_run_list) {
#   expected = %w(recipe[three])
#   chef_solo.run_list expected
#   assert_run_list(expected)
#   check_applied_recipes!(expected)
# }
}

namespace(:test_with_multiple_cookbooks) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_multiple_cookbooks", "test_with_multiple_cookbooks:setup"
  after "test_with_multiple_cookbooks", "test_with_multiple_cookbooks:teardown"

  task(:setup) {
    flush_attributes!
    set(:chef_solo_run_list, %w(recipe[bar] recipe[baz] recipe[two] recipe[three]))
    set(:chef_solo_cookbooks) {{
      "local" => {
        :scm => :none,
        :repository => File.expand_path("..", File.dirname(__FILE__)),
        :cookbooks => "config/cookbooks",
      },
      "repository" => {
        :scm => :git,
        :repository => "git://github.com/yyuu/capistrano-chef-solo.git",
        :revision => "develop",
        :cookbooks => "test/config/cookbooks2",
      },
    }}
    reset!(:chef_solo_cookbooks)
  }

  task(:teardown) {
  }

# task(:test_invoke) {
#   expected = chef_solo_run_list
#   find_and_execute_task("chef-solo")
#   assert_run_list(expected)
#   check_applied_recipes!(expected)
# }

# task(:test_run_list) {
#   expected = %w(recipe[foo] recipe[one])
#   chef_solo.run_list expected
#   assert_run_list(expected)
#   check_applied_recipes!(expected)
# }
}

# vim:set ft=ruby sw=2 ts=2 :
