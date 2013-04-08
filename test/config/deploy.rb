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
set :ssh_options, {
  :auth_methods => %w(publickey password),
  :keys => File.join(ENV["HOME"], ".vagrant.d", "insecure_private_key"),
  :user_known_hosts_file => "/dev/null",
}

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
  find_and_execute_task("test_with_bootstrap")
  find_and_execute_task("test_without_bootstrap")
}

def get_file(file, options={})
  tempfile = Tempfile.new("capistrano-chef-solo")
  top.get(file, tempfile.path, options)
  tempfile.read
end

def get_attributes(options={})
  JSON.load(get_file(chef_solo_attributes_file, options))
end

def assert_attributes(expected, options={})
  found = get_attributes(options)
  expected.each do |key, value|
    if found[key] != value
      abort("invalid attribute: #{key.inspect} (expected:#{value.inspect} != found:#{found[key].inspect})")
    end
  end
end

def assert_run_list(expected, options={})
  found = get_attributes(options)["run_list"]
  abort("invalid run_list (expected:#{expected.inspect} != found:#{found.inspect})") if found != expected
end

def assert_file_exists(file, options={})
  run("test -f #{file.dump}", options)
rescue
  abort("assert_file_exists(#{file}) failed.")
end

def assert_file_content(file, content, options={})
  remote_content = get_file(file, options)
  abort("assert_file_content(#{file}) failed. (expected=#{content.inspect}, got=#{remote_content.inspect})") if content != remote_content
end

def recipe_name(recipe)
  if /^recipe\[(\w+)\]$/ =~ recipe
    $1
  else
    abort("not a recipe: #{recipe}")
  end
end

def recipe_filename(recipe)
  File.join("/tmp", recipe_name(recipe))
end

def recipe_content(recipe)
  recipe_name(recipe).upcase
end

def _test_recipes(recipes, options={})
  recipes.each do |recipe|
    file = recipe_filename(recipe)
    body = recipe_content(recipe)
    begin
      assert_file_exists(file, options)
      assert_file_content(file, body, options)
    ensure
      sudo("rm -f #{file.dump}", options) rescue nil
    end
  end
end

def reset_chef_solo!()
  set(:chef_solo_attributes, {})
  set(:chef_solo_role_attributes, {})
  set(:chef_solo_host_attributes, {})
  set(:chef_solo_run_list, [])
  set(:chef_solo_role_run_list, {})
  set(:chef_solo_host_run_list, {})
  variables.each_key do |key|
    reset!(key) if /^chef_solo/ =~ key
  end
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
    reset_chef_solo!
    set(:chef_solo_attributes, {"aaa" => "AAA"})
    set(:chef_solo_role_attributes, {:app => {"bbb" => "BBB"}})
    set(:chef_solo_host_attributes, {"192.168.33.10" => {"ccc" => "CCC"}})
    set(:chef_solo_run_list, %w(recipe[foo]))
    set(:chef_solo_role_run_list, {:app => %w(recipe[bar])})
    set(:chef_solo_host_run_list, {"192.168.33.10" => %w(recipe[baz])})
    set(:chef_solo_capistrano_attributes_include, [:application, :deploy_to])
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
    assert_attributes({"application" => application, "deploy_to" => deploy_to})
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
    reset_chef_solo!
    set(:chef_solo_run_list, %w(recipe[foo] recipe[bar]))
    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_repository, File.expand_path("..", File.dirname(__FILE__)))
    set(:chef_solo_cookbooks_subdir, "config/cookbooks")
    set(:chef_solo_data_bags_scm, :none)
    set(:chef_solo_data_bags_repository, File.expand_path("..", File.dirname(__FILE__)))
    set(:chef_solo_data_bags_subdir, "config/data_bags")
  }

  task(:teardown) {
  }

  task(:test_invoke) {
    expected = chef_solo_run_list
    find_and_execute_task("chef-solo")
    assert_run_list(expected)
    _test_recipes(expected)
  }

  task(:test_run_list) {
    expected = %w(recipe[baz])
    chef_solo.run_list expected
    assert_run_list(expected)
    _test_recipes(expected)
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
    reset_chef_solo!
    set(:chef_solo_run_list, %w(recipe[one] recipe[two]))
    set(:chef_solo_cookbooks_scm, :git)
    set(:chef_solo_cookbooks_repository, "git://github.com/yyuu/capistrano-chef-solo.git")
    set(:chef_solo_cookbooks_revision, "support-data-bags2")
    set(:chef_solo_cookbooks_subdir, "test/config/cookbooks-ext")
    set(:chef_solo_data_bags_scm, :git)
    set(:chef_solo_data_bags_repository, "git://github.com/yyuu/capistrano-chef-solo.git")
    set(:chef_solo_data_bags_revision, "support-data-bags2")
    set(:chef_solo_data_bags_subdir, "test/config/data_bags-ext")
  }

  task(:teardown) {
  }

  task(:test_invoke) {
    expected = chef_solo_run_list
    find_and_execute_task("chef-solo")
    assert_run_list(expected)
    _test_recipes(expected)
  }

  task(:test_run_list) {
    expected = %w(recipe[three])
    chef_solo.run_list expected
    assert_run_list(expected)
    _test_recipes(expected)
  }
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
    reset_chef_solo!
    set(:chef_solo_run_list, %w(recipe[bar] recipe[baz] recipe[two] recipe[three]))
    set(:chef_solo_cookbooks) {{
      "local" => {
        :scm => :none,
        :repository => File.expand_path("..", File.dirname(__FILE__)),
        :cookbooks => "config/cookbooks",
      },
      "single" => {
        :cookbook_name => "single",
        :scm => :none,
        :repository => File.expand_path("..", File.dirname(__FILE__)),
        :cookbooks => "config/cookbook",
      },
      application => {
        :scm => :git,
        :repository => "git://github.com/yyuu/capistrano-chef-solo.git",
        :revision => "support-data-bags2",
        :cookbooks => "test/config/cookbooks-ext",
      },
    }}
    set(:chef_solo_data_bags) {{
      "local" => {
        :scm => :none,
        :repository => File.expand_path("..", File.dirname(__FILE__)),
        :data_bags => "config/data_bags",
      },
      "single" => {
        :data_bag_name => "single",
        :scm => :none,
        :repository => File.expand_path("..", File.dirname(__FILE__)),
        :data_bags => "config/data_bag",
      },
      application => {
        :scm => :git,
        :repository => "git://github.com/yyuu/capistrano-chef-solo.git",
        :revision => "support-data-bags2",
        :data_bags => "test/config/data_bags-ext",
      },
    }}
  }

  task(:teardown) {
  }

  task(:test_invoke) {
    expected = chef_solo_run_list
    find_and_execute_task("chef-solo")
    assert_run_list(expected)
    _test_recipes(expected)
  }

  task(:test_run_list) {
    expected = %w(recipe[foo] recipe[single] recipe[one])
    chef_solo.run_list expected
    assert_run_list(expected)
    _test_recipes(expected)
  }
}

namespace(:test_with_bootstrap) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_bootstrap", "test_with_bootstrap:setup"
  after "test_with_bootstrap", "test_with_bootstrap:teardown"

  task(:setup) {
    set(:chef_solo_bootstrap, true)
    set(:chef_solo_bootstrap_user, "bootstrap")
    set(:chef_solo_bootstrap_password, "bootstrap")
    set(:chef_solo_bootstrap_ssh_options, {
#     :auth_methods => %w(password), #==> setting :auth_methods throws Net::SSH::AuthenticationFailed (capistrano bug?)
      :user_known_hosts_file => "/dev/null",
    })
    run("getent passwd #{chef_solo_bootstrap_user.dump} || " +
        "#{sudo} useradd -m -p #{chef_solo_bootstrap_password.crypt(chef_solo_bootstrap_password).dump} #{chef_solo_bootstrap_user.dump}")
  }

  task(:teardown) {
    set(:chef_solo_bootstrap, false)
    unset(:chef_solo_bootstrap_user)
    unset(:chef_solo_bootstrap_password)
    unset(:chef_solo_bootstrap_ssh_options)
  }

  task(:test_connect_with_settings) {
    x = 0
    run("echo #{user.dump} = $(whoami) && test vagrant = $(whoami)")
    chef_solo.connect_with_settings do
      x += 1
      run("echo #{user.dump} = $(whoami) && test bootstrap = $(whoami)")
      chef_solo.connect_with_settings do
        x += 1
        run("echo #{user.dump} = $(whoami) && test bootstrap = $(whoami)")
      end
      x += 1
      run("echo #{user.dump} = $(whoami) && test bootstrap = $(whoami)")
    end
    x += 1
    run("echo #{user.dump} = $(whoami) && echo test vagrant = $(whoami)")
    abort("some clauses may be skipped") if x != 4
  }
}

namespace(:test_without_bootstrap) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_without_bootstrap", "test_without_bootstrap:setup"
  after "test_without_bootstrap", "test_without_bootstrap:teardown"

  task(:setup) {
    set(:chef_solo_bootstrap, false)
    set(:chef_solo_bootstrap_user, "bootstrap")
    set(:chef_solo_bootstrap_password, "bootstrap")
    set(:chef_solo_bootstrap_ssh_options, {:user_known_hosts_file => "/dev/null"})
  }

  task(:teardown) {
    set(:chef_solo_bootstrap, false)
    unset(:chef_solo_bootstrap_user)
    unset(:chef_solo_bootstrap_password)
    unset(:chef_solo_bootstrap_ssh_options)
  }

  task(:test_connect_with_settings) {
    x = 0
    run("echo #{user.dump} = $(whoami) && test vagrant = $(whoami)")
    chef_solo.connect_with_settings do
      x += 1
      run("echo #{user.dump} = $(whoami) && test vagrant = $(whoami)")
      chef_solo.connect_with_settings do
        x += 1
        run("echo #{user.dump} = $(whoami) && test vagrant = $(whoami)")
      end
      x += 1
      run("echo #{user.dump} = $(whoami) && test vagrant = $(whoami)")
    end
    x += 1
    run("echo #{user.dump} = $(whoami) && echo test vagrant = $(whoami)")
    abort("some clauses may be skipped") if x != 4
  }
}
# vim:set ft=ruby sw=2 ts=2 :
