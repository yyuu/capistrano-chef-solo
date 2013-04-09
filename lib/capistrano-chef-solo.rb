require "capistrano-chef-solo/version"
require "capistrano-rbenv"
require "capistrano/configuration"
require "capistrano/recipes/deploy/scm"
require "json"
require "uri"

module Capistrano
  module ChefSolo
    def self.extended(configuration)
      configuration.load {
        namespace(:"chef-solo") {
          desc("Setup chef-solo. (an alias of chef_solo:setup)")
          task(:setup, :except => { :no_release => true }) {
            find_and_execute_task("chef_solo:setup")
          }

          desc("Run chef-solo. (an alias of chef_solo)")
          task(:default, :except => { :no_release => true }) {
            find_and_execute_task("chef_solo:default")
          }

          desc("Show chef-solo version. (an alias of chef_solo:version)")
          task(:version, :except => { :no_release => true }) {
            find_and_execute_task("chef_solo:version")
          }

          desc("Show chef-solo attributes. (an alias of chef_solo:attributes)")
          task(:attributes, :except => { :no_release => true }) {
            find_and_execute_task("chef_solo:attributes")
          }
        }

        namespace(:chef_solo) {
          _cset(:chef_solo_version, "11.4.0")
          _cset(:chef_solo_path) { capture("echo $HOME/chef").strip }
          _cset(:chef_solo_cache_path) { File.join(chef_solo_path, "cache") }
          _cset(:chef_solo_config_path) { File.join(chef_solo_path, "config") }
          _cset(:chef_solo_cookbooks_path) { File.join(chef_solo_path, "cookbooks") }
          _cset(:chef_solo_data_bags_path) { File.join(chef_solo_path, "data_bags") }
          _cset(:chef_solo_config_file) { File.join(chef_solo_config_path, "solo.rb") }
          _cset(:chef_solo_attributes_file) { File.join(chef_solo_config_path, "solo.json") }

          _cset(:chef_solo_bootstrap_user) {
            if variables.key?(:chef_solo_user)
              logger.info(":chef_solo_user has been deprecated. use :chef_solo_bootstrap_user instead.")
              fetch(:chef_solo_user, user)
            else
              user
            end
          }
          _cset(:chef_solo_bootstrap_password) { password }
          _cset(:chef_solo_bootstrap_ssh_options) {
            if variables.key?(:chef_solo_ssh_options)
              logger.info(":chef_solo_ssh_options has been deprecated. use :chef_solo_bootstrap_ssh_options instead.")
              fetch(:chef_solo_ssh_options, ssh_options)
            else
              ssh_options
            end
          }
          _cset(:chef_solo_use_password) {
            auth_methods = ssh_options.fetch(:auth_methods, []).map { |m| m.to_sym }
            auth_methods.include?(:password) or auth_methods.empty?
          }

          _cset(:_chef_solo_bootstrapped, false)
          def _activate_settings(servers=[])
            if _chef_solo_bootstrapped
              false
            else
              # preserve original :user and :ssh_options
              set(:_chef_solo_bootstrap_user, fetch(:user))
              set(:_chef_solo_bootstrap_password, fetch(:password)) if chef_solo_use_password
              set(:_chef_solo_bootstrap_ssh_options, fetch(:ssh_options))
              # we have to establish connections before teardown.
              # https://github.com/capistrano/capistrano/pull/416
              establish_connections_to(servers)
              logger.info("entering chef-solo bootstrap mode. reconnect to servers as `#{chef_solo_bootstrap_user}'.")
              # drop connection which is connected as standard :user.
              teardown_connections_to(servers)
              set(:user, chef_solo_bootstrap_user)
              set(:password, chef_solo_bootstrap_password) if chef_solo_use_password
              set(:ssh_options, chef_solo_bootstrap_ssh_options)
              set(:_chef_solo_bootstrapped, true)
              true
            end
          end

          def _deactivate_settings(servers=[])
            if _chef_solo_bootstrapped
              set(:user, _chef_solo_bootstrap_user)
              set(:password, _chef_solo_bootstrap_password) if chef_solo_use_password
              set(:ssh_options, _chef_solo_bootstrap_ssh_options)
              set(:_chef_solo_bootstrapped, false)
              # we have to establish connections before teardown.
              # https://github.com/capistrano/capistrano/pull/416
              establish_connections_to(servers)
              logger.info("leaving chef-solo bootstrap mode. reconnect to servers as `#{user}'.")
              # drop connection which is connected as bootstrap :user.
              teardown_connections_to(servers)
              true
            else
              false
            end
          end

          _cset(:chef_solo_bootstrap, false)
          def connect_with_settings(&block)
            if chef_solo_bootstrap
              servers = find_servers
              if block_given?
                begin
                  activated = _activate_settings(servers)
                  yield
                rescue => error
                  logger.info("could not connect with bootstrap settings: #{error}")
                  raise
                ensure
                  _deactivate_settings(servers) if activated
                end
              else
                _activate_settings(servers)
              end
            else
              yield if block_given?
            end
          end

          # FIXME:
          # Some variables (such like :default_environment set by capistrano-rbenv) may be
          # initialized without bootstrap settings during `on :load`.
          # Is there any way to avoid this without setting `:rbenv_setup_default_environment`
          # as false?
          set(:rbenv_setup_default_environment, false)

          desc("Setup chef-solo.")
          task(:setup, :except => { :no_release => true }) {
            connect_with_settings do
              transaction do
                install
              end
            end
          }

          desc("Run chef-solo.")
          task(:default, :except => { :no_release => true }) {
            connect_with_settings do
              setup
              transaction do
                update
                invoke
              end
            end
          }

          # Acts like `default`, but will apply specified recipes only.
          def run_list(*recipes)
            connect_with_settings do
              setup
              transaction do
                update(:run_list => recipes)
                invoke
              end
            end
          end

          _cset(:chef_solo_cmd, "chef-solo")

          desc("Show chef-solo version.")
          task(:version, :except => { :no_release => true }) {
            connect_with_settings do
              run("cd #{chef_solo_path.dump} && #{bundle_cmd} exec #{chef_solo_cmd} --version")
            end
          }

          desc("Show chef-solo attributes.")
          task(:attributes, :except => { :no_release => true }) {
            hosts = ENV.fetch("HOST", "").split(/\s*,\s*/)
            roles = ENV.fetch("ROLE", "").split(/\s*,\s*/).map { |role| role.to_sym }
            roles += hosts.map { |host| role_names_for_host(ServerDefinition.new(host)) }
            attributes = _generate_attributes(:hosts => hosts, :roles => roles)
            STDOUT.puts(_json_attributes(attributes))
          }

          task(:install, :except => { :no_release => true }) {
            install_ruby
            install_chef
          }

          task(:install_ruby, :except => { :no_release => true }) {
            set(:rbenv_install_bundler, true)
            find_and_execute_task("rbenv:setup")
          }

          _cset(:chef_solo_gemfile) {
            (<<-EOS).gsub(/^\s*/, "")
              source "https://rubygems.org"
              gem "chef", #{chef_solo_version.to_s.dump}
            EOS
          }
          task(:install_chef, :except => { :no_release => true }) {
            begin
              version = capture("cd #{chef_solo_path.dump} && #{bundle_cmd} exec #{chef_solo_cmd} --version")
              installed = Regexp.new(Regexp.escape(chef_solo_version)) =~ version
            rescue
              installed = false
            end
            unless installed
              dirs = [ chef_solo_path, chef_solo_cache_path, chef_solo_config_path ].uniq
              run("mkdir -p #{dirs.map { |x| x.dump }.join(" ")}")
              top.put(chef_solo_gemfile, File.join(chef_solo_path, "Gemfile"))
              args = fetch(:chef_solo_bundle_options, [])
              args << "--path=#{File.join(chef_solo_path, "bundle").dump}"
              args << "--quiet"
              run("cd #{chef_solo_path.dump} && #{bundle_cmd} install #{args.join(" ")}")
            end
          }
 
          def update(options={})
            update_cookbooks(options)
            update_data_bags(options)
            update_attributes(options)
            update_config(options)
          end

          def update_cookbooks(options={})
            repos = _normalize_cookbooks(chef_solo_cookbooks)
            _install_repos(:cookbooks, repos, chef_solo_cookbooks_path, options) do |name, tmpdir, variables|
              deploy_cookbooks(name, tmpdir, variables, options)
            end
          end

          def update_data_bags(options={})
            repos = _normalize_data_bags(chef_solo_data_bags)
            _install_repos(:data_bags, repos, chef_solo_data_bags_path, options) do |name, tmpdir, variables|
              deploy_data_bags(name, tmpdir, variables, options)
            end
          end

          def _install_repos(t, repos, destination, options={}, &block)
            # (0) remove existing old data
            run("rm -rf #{destination.dump} && mkdir -p #{destination.dump}", options)
            repos.each do |name, variables|
              begin
                tmpdir = capture("mktemp -d #{File.join("/tmp", "#{t}.XXXXXXXXXX").dump}", options).strip
                run("rm -rf #{tmpdir.dump} && mkdir -p #{tmpdir.dump}", options)
                # (1) caller deploys the repository to tmpdir
                yield name, tmpdir, variables
                # (2) then deploy it to actual destination
                logger.debug("installing #{t} `#{name}' from #{tmpdir} to #{destination}.")
                run("rsync -lrpt #{(tmpdir + "/").dump} #{destination.dump}", options)
              ensure
                run("rm -rf #{tmpdir.dump}", options)
              end
            end
          end

          _cset(:chef_solo_repository_cache) { File.expand_path("tmp") }
          _cset(:chef_solo_repository_exclude, %w(.hg .git .svn))
          _cset(:chef_solo_repository_variables) {{
            :scm => :none,
            :deploy_via => :copy_subdir,
            :deploy_subdir => nil,
            :repository => ".",
            :copy_cache => nil,
          }}

          #
          # The definition of cookbooks.
          # By default, load cookbooks from local path of "config/cookbooks".
          #
          _cset(:chef_solo_cookbooks_exclude) { chef_solo_repository_exclude }
          _cset(:chef_solo_cookbooks_variables) { chef_solo_repository_variables.merge(:copy_exclude => chef_solo_cookbooks_exclude) }
          _cset(:chef_solo_cookbooks) { _default_repos(:cookbook, chef_solo_cookbooks_variables) }
          _cset(:chef_solo_cookbooks_cache) { File.join(chef_solo_repository_cache, "cookbooks-cache") }
          def _normalize_cookbooks(repos)
            _normalize_repos(repos, chef_solo_cookbooks_cache, chef_solo_cookbooks_variables) { |name, variables|
              variables[:deploy_subdir] ||= variables[:cookbooks] # use :cookbooks as :deploy_subdir for backward compatibility with prior than 0.1.2
              variables[:copy_exclude] ||= variables[:cookbooks_exclude]
            }
          end

          #
          # The definition of data_bags.
          # By default, load data_bags from local path of "config/data_bags".
          #
          _cset(:chef_solo_data_bags_exclude) { chef_solo_repository_exclude }
          _cset(:chef_solo_data_bags_variables) { chef_solo_repository_variables.merge(:copy_exclude => chef_solo_data_bags_exclude) }
          _cset(:chef_solo_data_bags) { _default_repos(:data_bag, chef_solo_data_bags_variables) }
          _cset(:chef_solo_data_bags_cache) { File.join(chef_solo_repository_cache, "data_bags-cache") }
          def _normalize_data_bags(repos)
            _normalize_repos(repos, chef_solo_data_bags_cache, chef_solo_data_bags_variables) { |name, variables|
              variables[:deploy_subdir] ||= variables[:data_bags] # use :data_bags as :deploy_subdir for backward compatibility with prior than 0.1.2
              variables[:copy_exclude] ||= variables[:data_bags_exclude]
            }
          end

          def _default_repos(singular, variables={}, &block)
            plural = "#{singular}s"
            variables = variables.dup
            variables[:scm] = fetch("chef_solo_#{plural}_scm".to_sym) if exists?("chef_solo_#{plural}_scm".to_sym)
            variables[:deploy_subdir] = fetch("chef_solo_#{plural}_subdir".to_sym, File.join("config", plural))
            variables[:repository] = fetch("chef_solo_#{plural}_repository".to_sym) if exists?("chef_solo_#{plural}_repository".to_sym)
            variables[:revision] = fetch("chef_solo_#{plural}_revision".to_sym) if exists?("chef_solo_#{plural}_revision".to_sym)
            if exists?("chef_solo_#{singular}_name".to_sym)
              name = fetch("chef_solo_#{singular}_name".to_sym) # deploy as single cookbook
              variables["#{singular}_name".to_sym] = name
            else
              name = fetch("chef_solo_#{plural}_name".to_sym, application) # deploy as multiple cookbooks
            end
            { name => variables }
          end

          def _normalize_repos(repos, cache_path, default_variables={}, &block)
            normalized = repos.map { |name, variables|
              variables = default_variables.merge(variables)
              variables[:application] ||= name
              if variables[:scm] != :none
                variables[:copy_cache] ||= File.expand_path(name, cache_path)
              end
              yield name, variables
              [name, variables]
            }
            Hash[normalized]
          end

          def deploy_cookbooks(name, destination, variables={}, options={})
            # deploy as single cookbook, or deploy as multiple cookbooks
            final_destination = variables.key?(:cookbook_name) ? File.join(destination, variables[:cookbook_name]) : destination
            _deploy_repo(:cookbooks, name, final_destination, variables, options)
          end

          def deploy_data_bags(name, destination, variables={}, options={})
            # deploy as single data_bag, or deploy as multiple data_bags
            final_destination = variables.key?(:data_bag_name) ? File.join(destination, variables[:data_bag_name]) : destination
            _deploy_repo(:data_bags, name, final_destination, variables, options)
          end

          def _deploy_repo(t, name, destination, variables={}, options={})
            begin
              releases_path = capture("mktemp -d /tmp/releases.XXXXXXXXXX", options).strip
              release_path = File.join(releases_path, release_name)
              run("rm -rf #{releases_path.dump} && mkdir -p #{releases_path.dump}", options)
              c = _middle_copy(top) # create new configuration with separated @variables
              c.instance_eval do
                set(:deploy_to, File.dirname(releases_path))
                set(:releases_path, releases_path)
                set(:release_path, release_path)
                set(:revision) { source.head }
                set(:source) { ::Capistrano::Deploy::SCM.new(scm, self) }
                set(:real_revision) { source.local.query_revision(revision) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } } }
                set(:strategy) { ::Capistrano::Deploy::Strategy.new(deploy_via, self) }
                variables.each do |key, val|
                  if val.nil?
                    unset(key)
                  else
                    set(key, val)
                  end
                end
                from = File.join(repository, fetch(:deploy_subdir, "/"))
                to = destination
                logger.debug("retrieving #{t} `#{name}' from #{from} (scm=#{scm}, via=#{deploy_via}) to #{to}.")
                strategy.deploy!
              end
              run("rsync -lrpt #{(release_path + "/").dump} #{destination.dump}", options)
            ensure
              run("rm -rf #{releases_path.dump}", options)
            end
          end

          def _middle_copy(object)
            o = object.clone
            object.instance_variables.each do |k|
              v = object.instance_variable_get(k)
              o.instance_variable_set(k, v ? v.clone : v)
            end
            o
          end

          _cset(:chef_solo_config) {
            (<<-EOS).gsub(/^\s*/, "")
              file_cache_path #{chef_solo_cache_path.dump}
              cookbook_path #{chef_solo_cookbooks_path.dump}
              data_bag_path #{chef_solo_data_bags_path.dump}
            EOS
          }
          def update_config(options={})
            top.put(chef_solo_config, chef_solo_config_file, options)
          end

          # merge nested hashes
          def _merge_attributes!(a, b)
            f = lambda { |key, val1, val2|
              case val1
              when Array
                val1 + val2
              when Hash
                val1.merge(val2, &f)
              else
                val2
              end
            }
            a.merge!(b, &f)
          end

          def _json_attributes(x)
            JSON.send(fetch(:chef_solo_pretty_json, true) ? :pretty_generate : :generate, x)
          end

          _cset(:chef_solo_capistrano_attributes) {
            #
            # The rule of generating chef attributes from Capistrano variables
            #
            # 1. Reject variables if it is in exclude list.
            # 2. Reject variables if it is lazy and not in include list.
            #    (lazy variables might have any side-effects)
            #
            attributes = variables.reject { |key, value|
              excluded = chef_solo_capistrano_attributes_exclude.include?(key)
              included = chef_solo_capistrano_attributes_include.include?(key)
              excluded or (not included and value.respond_to?(:call))
            }
            Hash[attributes.map { |key, value| [key, fetch(key, nil)] }]
          }
          _cset(:chef_solo_capistrano_attributes_include, [
            :application, :deploy_to, :rails_env, :latest_release,
            :releases_path, :shared_path, :current_path, :release_path,
          ])
          _cset(:chef_solo_capistrano_attributes_exclude, [:logger, :password])
          _cset(:chef_solo_attributes, {})
          _cset(:chef_solo_host_attributes, {})
          _cset(:chef_solo_role_attributes, {})
          _cset(:chef_solo_run_list, [])
          _cset(:chef_solo_host_run_list, {})
          _cset(:chef_solo_role_run_list, {})

          def _generate_attributes(options={})
            hosts = [ options.delete(:hosts) ].flatten.compact.uniq
            roles = [ options.delete(:roles) ].flatten.compact.uniq
            run_list = [ options.delete(:run_list) ].flatten.compact.uniq
            #
            # By default, the Chef attributes will be generated by following order.
            # 
            # 1. Use _non-lazy_ variables of Capistrano.
            # 2. Use attributes defined in `:chef_solo_attributes`.
            # 3. Use attributes defined in `:chef_solo_role_attributes` for target role.
            # 4. Use attributes defined in `:chef_solo_host_attributes` for target host.
            #
            attributes = chef_solo_capistrano_attributes.dup
            _merge_attributes!(attributes, chef_solo_attributes)
            roles.each do |role|
              _merge_attributes!(attributes, chef_solo_role_attributes.fetch(role, {}))
            end
            hosts.each do |host|
              _merge_attributes!(attributes, chef_solo_host_attributes.fetch(host, {}))
            end
            #
            # The Chef `run_list` will be generated by following rules.
            #
            # * If `:run_list` was given as argument, just use it.
            # * Otherwise, generate it from `:chef_solo_role_run_list`, `:chef_solo_role_run_list`
            #   and `:chef_solo_host_run_list`.
            #
            if run_list.empty?
              _merge_attributes!(attributes, {"run_list" => chef_solo_run_list})
              roles.each do |role|
                _merge_attributes!(attributes, {"run_list" => chef_solo_role_run_list.fetch(role, [])})
              end
              hosts.each do |host|
                _merge_attributes!(attributes, {"run_list" => chef_solo_host_run_list.fetch(host, [])})
              end
            else
              attributes["run_list"] = [] # ignore run_list not from argument
              _merge_attributes!(attributes, {"run_list" => run_list})
            end
            attributes
          end

          def update_attributes(options={})
            run_list = options.delete(:run_list)
            servers = find_servers_for_task(current_task)
            servers.each do |server|
              logger.debug("updating chef-solo attributes for #{server.host}.")
              attributes = _generate_attributes(:hosts => server.host, :roles => role_names_for_host(server), :run_list => run_list)
              top.put(_json_attributes(attributes), chef_solo_attributes_file, options.merge(:hosts => server.host))
            end
          end

          def invoke(options={})
            logger.debug("invoking chef-solo.")
            args = fetch(:chef_solo_options, [])
            args << "-c #{chef_solo_config_file.dump}"
            args << "-j #{chef_solo_attributes_file.dump}"
            run("cd #{chef_solo_path.dump} && #{sudo} #{bundle_cmd} exec #{chef_solo_cmd} #{args.join(" ")}", options)
          end
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::ChefSolo)
end

# vim:set ft=ruby ts=2 sw=2 :
