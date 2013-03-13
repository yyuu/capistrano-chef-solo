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
          _cset(:chef_solo_path_children, %w(bundle cache config cookbooks))
          _cset(:chef_solo_config_file) { File.join(chef_solo_path, "config", "solo.rb") }
          _cset(:chef_solo_attributes_file) { File.join(chef_solo_path, "config", "solo.json") }

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
          def _bootstrap_settings(&block)
            if fetch(:_chef_solo_bootstrapped, false)
              yield
            else
              # preserve original :user and :ssh_options
              set(:_chef_solo_bootstrap_user, fetch(:user))
              set(:_chef_solo_bootstrap_password, fetch(:password)) if chef_solo_use_password
              set(:_chef_solo_bootstrap_ssh_options, fetch(:ssh_options))
              begin
                set(:user, chef_solo_bootstrap_user)
                set(:password, chef_solo_bootstrap_password) if chef_solo_use_password
                set(:ssh_options, chef_solo_bootstrap_ssh_options)
                set(:_chef_solo_bootstrapped, true)
                teardown_connections_to(find_servers) # drop current connections
                yield
              ensure
                set(:user, _chef_solo_bootstrap_user)
                set(:password, _chef_solo_bootstrap_password) if chef_solo_use_password
                set(:ssh_options, _chef_solo_bootstrap_ssh_options)
                set(:_chef_solo_bootstrapped, false)
                teardown_connections_to(find_servers) # drop bootstrap connections
              end
            end
          end
          #
          # Let's say you have two users on target servers.
          #
          # * ubuntu - the default user of system, created by system installer.
          #            use this for bootstrap.
          # * deploy - the user to use for application deployments.
          #            will be created during bootstrap.
          #
          # Then, set these users in your Capfile.
          #
          #     set(:user, "deploy")
          #     set(:chef_solo_bootstrap_user, "ubuntu")
          #
          # To bootstrap the system from clean installation:
          #
          #     % cap -S chef_solo_bootstrap=true chef-solo
          #
          # After the bootstrap, there is `deploy` user:
          #
          #     % cap deploy:setup
          #
          _cset(:chef_solo_bootstrap, false)
          def connect_with_settings(&block)
            if chef_solo_bootstrap
              _bootstrap_settings do
                yield
              end
            else
              yield
            end
          end

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

          desc("Show chef-solo version.")
          task(:version, :except => { :no_release => true }) {
            connect_with_settings do
              run("cd #{chef_solo_path.dump} && #{bundle_cmd} exec chef-solo --version")
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
              version = capture("cd #{chef_solo_path.dump} && #{bundle_cmd} exec chef-solo --version")
              installed = Regexp.new(Regexp.escape(chef_solo_version)) =~ version
            rescue
              installed = false
            end
            unless installed
              dirs = chef_solo_path_children.map { |dir| File.join(chef_solo_path, dir) }
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
            update_config(options)
            update_attributes(options)
          end

          def update_cookbooks(options={})
            tmpdir = run_locally("mktemp -d /tmp/chef-solo.XXXXXXXXXX").strip
            remote_tmpdir = capture("mktemp -d /tmp/chef-solo.XXXXXXXXXX").strip
            destination = File.join(tmpdir, "cookbooks")
            remote_destination = File.join(chef_solo_path, "cookbooks")
            filename = File.join(tmpdir, "cookbooks.tar.gz")
            remote_filename = File.join(remote_tmpdir, "cookbooks.tar.gz")
            begin
              bundle_cookbooks(filename, destination)
              run("mkdir -p #{remote_tmpdir.dump}")
              distribute_cookbooks(filename, remote_filename, remote_destination)
            ensure
              run("rm -rf #{remote_tmpdir.dump}") rescue nil
              run_locally("rm -rf #{tmpdir.dump}") rescue nil
            end
          end

          #
          # The definition of cookbooks.
          # By default, load cookbooks from local path of "config/cookbooks".
          #
          _cset(:chef_solo_cookbooks_name) { application }
          _cset(:chef_solo_cookbooks_scm, :none)
          _cset(:chef_solo_cookbooks) {
            cookbooks = {}
            cookbooks[chef_solo_cookbooks_name] = {}
            cookbooks[chef_solo_cookbooks_name][:cookbooks] = fetch(:chef_solo_cookbooks_subdir, "config/cookbooks")
            cookbooks[chef_solo_cookbooks_name][:repository] = fetch(:chef_solo_cookbooks_repository) if exists?(:chef_solo_cookbooks_repository)
            cookbooks[chef_solo_cookbooks_name][:revision] = fetch(:chef_solo_cookbooks_revision) if exists?(:chef_solo_cookbooks_revision)
            cookbooks
          }

          _cset(:chef_solo_cookbooks_exclude, %w(.hg .git .svn))
          def _normalize_cookbooks(cookbooks)
            xs = cookbooks.map { |name, options|
              options[:scm] ||= chef_solo_cookbooks_scm
              options[:cookbooks_exclude] ||= chef_solo_cookbooks_exclude
              [name, options]
            }
            Hash[xs]
          end

          _cset(:chef_solo_repository_cache) { File.expand_path("./tmp/cookbooks-cache") }
          def bundle_cookbooks(filename, destination)
            dirs = [ File.dirname(filename), destination ].uniq
            run_locally("mkdir -p #{dirs.map { |x| x.dump }.join(" ")}")
            cookbooks = _normalize_cookbooks(chef_solo_cookbooks)
            cookbooks.each do |name, options|
              case options[:scm].to_sym
              when :none
                fetch_cookbooks_none(name, destination, options)
              else
                fetch_cookbooks_repository(name, destination, options)
              end
            end
            run_locally("cd #{File.dirname(destination).dump} && tar chzf #{filename.dump} #{File.basename(destination).dump}")
          end

          def _fetch_cookbook(source, destination, options)
            exclusions = options.fetch(:cookbooks_exclude, []).map { |e| "--exclude=#{e.dump}" }.join(" ")
            run_locally("rsync -lrpt #{exclusions} #{source}/ #{destination}")
          end

          def _fetch_cookbooks(source, destination, options)
            cookbooks = [ options.fetch(:cookbooks, "/") ].flatten.compact
            cookbooks.each do |cookbook|
              _fetch_cookbook(File.join(source, cookbook), destination, options)
            end
          end

          def fetch_cookbooks_none(name, destination, options={})
            _fetch_cookbooks(options.fetch(:repository, "."), destination, options)
          end

          def fetch_cookbooks_repository(name, destination, options={})
            configuration = Capistrano::Configuration.new
            # refreshing just :source, :revision and :real_revision is enough?
            options = {
              :source => lambda { Capistrano::Deploy::SCM.new(configuration[:scm], configuration) },
              :revision => lambda { configuration[:source].head },
              :real_revision => lambda {
                configuration[:source].local.query_revision(configuration[:revision]) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } }
              },
            }.merge(options)
            variables.merge(options).each do |key, val|
              configuration.set(key, val)
            end
            repository_cache = File.join(chef_solo_repository_cache, name)
            if File.exist?(repository_cache)
              run_locally(configuration[:source].sync(configuration[:real_revision], repository_cache))
            else
              run_locally(configuration[:source].checkout(configuration[:real_revision], repository_cache))
            end
            _fetch_cookbooks(repository_cache, destination, options)
          end

          def distribute_cookbooks(filename, remote_filename, remote_destination)
            upload(filename, remote_filename)
            run("rm -rf #{remote_destination.dump}")
            run("cd #{File.dirname(remote_destination).dump} && tar xzf #{remote_filename.dump}")
          end

          _cset(:chef_solo_config) {
            (<<-EOS).gsub(/^\s*/, "")
              file_cache_path #{File.join(chef_solo_path, "cache").dump}
              cookbook_path #{File.join(chef_solo_path, "cookbooks").dump}
            EOS
          }
          def update_config(options={})
            top.put(chef_solo_config, chef_solo_config_file)
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
              attributes = _generate_attributes(:hosts => server.host, :roles => role_names_for_host(server), :run_list => run_list)
              top.put(_json_attributes(attributes), chef_solo_attributes_file, options.merge(:hosts => server.host))
            end
          end

          def invoke(options={})
            bin = fetch(:chef_solo_executable, "chef-solo")
            args = fetch(:chef_solo_options, [])
            args << "-c #{chef_solo_config_file.dump}"
            args << "-j #{chef_solo_attributes_file.dump}"
            run("cd #{chef_solo_path.dump} && #{sudo} #{bundle_cmd} exec #{bin.dump} #{args.join(" ")}", options)
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
