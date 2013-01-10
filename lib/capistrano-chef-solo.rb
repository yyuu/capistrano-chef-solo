require 'capistrano-chef-solo/version'
require 'capistrano-rbenv'
require 'capistrano/configuration'
require 'capistrano/recipes/deploy/scm'
require 'capistrano/transfer'
require 'json'
require 'tmpdir'
require 'uri'

module Capistrano
  module ChefSolo
    def self.extended(configuration)
      configuration.load {
        namespace(:"chef-solo") {
          _cset(:chef_solo_home) {
            capture('echo $HOME').strip
          }
          _cset(:chef_solo_version, '10.16.4')
          _cset(:chef_solo_path) { File.join(chef_solo_home, 'chef') }
          _cset(:chef_solo_path_children, %w(bundle cache config cookbooks))

          desc("Run chef-solo.")
          task(:default) {
            # preserve original :user and :ssh_options
            set(:chef_solo_original_user, user)
            set(:chef_solo_original_ssh_options, ssh_options)

            begin
              # login as chef user if specified
              set(:user, fetch(:chef_solo_user, user))
              set(:ssh_options, fetch(:chef_solo_ssh_options, ssh_options))

              transaction {
                bootstrap
                update
              }
            ensure
              # restore original :user and :ssh_options
              set(:user, chef_solo_original_user)
              set(:ssh_options, chef_solo_original_ssh_options)
            end
          }

          task(:bootstrap) {
            install_ruby
            install_chef
          }

          _cset(:chef_solo_ruby_version) {
            rbenv_ruby_version
          }
          task(:install_ruby) {
            set(:rbenv_ruby_version, chef_solo_ruby_version)
            set(:rbenv_use_bundler, true)
            find_and_execute_task('rbenv:setup')
          }

          _cset(:chef_solo_gemfile) {
            (<<-EOS).gsub(/^\s*/, '')
              source "https://rubygems.org"
              gem "chef", #{chef_solo_version.to_s.dump}
            EOS
          }
          task(:install_chef) {
            dirs = chef_solo_path_children.map { |dir| File.join(chef_solo_path, dir) }
            run("mkdir -p #{dirs.join(' ')}")
            put(chef_solo_gemfile, "#{File.join(chef_solo_path, 'Gemfile')}")
            run("cd #{chef_solo_path} && #{bundle_cmd} install --path=#{chef_solo_path}/bundle --quiet")
          }
 
          task(:update) {
            update_cookbooks
            update_config
            update_attributes
            invoke
          }

          task(:update_cookbooks) {
            tmpdir = Dir.mktmpdir()
            remote_tmpdir = capture("mktemp -d").chomp
            destination = File.join(tmpdir, 'cookbooks')
            remote_destination = File.join(chef_solo_path, 'cookbooks')
            filename = File.join(tmpdir, 'cookbooks.tar.gz')
            remote_filename = File.join(remote_tmpdir, 'cookbooks.tar.gz')
            begin
              bundle_cookbooks(filename, destination)
              run("mkdir -p #{remote_tmpdir}")
              distribute_cookbooks(filename, remote_filename, remote_destination)
            ensure
              run("rm -rf #{remote_tmpdir}") rescue nil
              run_locally("rm -rf #{tmpdir}") rescue nil
            end
          }

          # s/cookbook/&s/g for backward compatibility with releases older than 0.0.2.
          # they will be removed in future releases.
          _cset(:chef_solo_cookbook_repository) {
            logger.info("WARNING: `chef_solo_cookbook_repository' has been deprecated. use `chef_solo_cookbooks_repository' instead.")
            abort("chef_solo_cookbook_repository not set")
          }
          _cset(:chef_solo_cookbook_revision) {
            logger.info("WARNING: `chef_solo_cookbook_revision' has been deprecated. use `chef_solo_cookbooks_revision' instead.")
            "HEAD"
          }
          _cset(:chef_solo_cookbook_subdir) {
            logger.info("WARNING: `chef_solo_cookbook_subdir' has been deprecated. use `chef_solo_cookbooks_subdir' instead.")
            "/"
          }
          _cset(:chef_solo_cookbooks_exclude, %w(.hg .git .svn))

          # special variable to set multiple cookbooks repositories.
          # by default, it will build from :chef_solo_cookbooks_* variables.
          _cset(:chef_solo_cookbooks) {
            repository = fetch(:chef_solo_cookbooks_repository, nil)
            repository = fetch(:chef_solo_cookbook_repository, nil) unless repository # for backward compatibility
            name = File.basename(repository, File.extname(repository))
            options = { :repository => repository, :cookbooks_exclude => chef_solo_cookbooks_exclude }
            options[:revision] = fetch(:chef_solo_cookbooks_revision, nil)
            options[:revision] = fetch(:chef_solo_cookbook_revision, nil) unless options[:revision] # for backward compatibility
            options[:cookbooks] = fetch(:chef_solo_cookbooks_subdir, nil)
            options[:cookbooks] = fetch(:chef_solo_cookbook_subdir, nil) unless options[:cookbooks] # for backward compatibility
            { name => options }
          }

          _cset(:chef_solo_repository_cache) { File.expand_path('./tmp/cookbooks-cache') }
          def bundle_cookbooks(filename, destination)
            dirs = [ File.dirname(filename), destination ].uniq
            run_locally("mkdir -p #{dirs.join(' ')}")
            chef_solo_cookbooks.each do |name, options|
              configuration = Capistrano::Configuration.new()
              # refreshing just :source, :revision and :real_revision is enough?
              options = {
                :source => proc { Capistrano::Deploy::SCM.new(configuration[:scm], configuration) },
                :revision => proc { configuration[:source].head },
                :real_revision => proc {
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

              cookbooks = [ options.fetch(:cookbooks, '/') ].flatten.compact
              execute = cookbooks.map { |c|
                repository_cache_subdir = File.join(repository_cache, c)
                exclusions = options.fetch(:cookbooks_exclude, []).map { |e| "--exclude=\"#{e}\"" }.join(' ')
                "rsync -lrpt #{exclusions} #{repository_cache_subdir}/ #{destination}"
              }
              run_locally(execute.join(' && '))
            end
            run_locally("cd #{File.dirname(destination)} && tar chzf #{filename} #{File.basename(destination)}")
          end

          def distribute_cookbooks(filename, remote_filename, remote_destination)
            upload(filename, remote_filename)
            run("rm -rf #{remote_destination}")
            run("cd #{File.dirname(remote_destination)} && tar xzf #{remote_filename}")
          end

          _cset(:chef_solo_config) {
            (<<-EOS).gsub(/^\s*/, '')
              file_cache_path #{File.join(chef_solo_path, 'cache').dump}
              cookbook_path #{File.join(chef_solo_path, 'cookbooks').dump}
            EOS
          }
          task(:update_config) {
            put(chef_solo_config, File.join(chef_solo_path, 'config', 'solo.rb'))
          }

          # merge nested hashes
          def _deep_merge(a, b)
            f = lambda { |key, val1, val2| Hash === val1 && Hash === val2 ? val1.merge(val2, &f) : val2 }
            a.merge(b, &f)
          end

          def _json(x)
            if fetch(:chef_solo_pretty_json, true)
              JSON.pretty_generate(x)
            else
              JSON.generate(x)
            end
          end

          _cset(:chef_solo_attributes, {})
          _cset(:chef_solo_host_attributes, {})
          task(:update_attributes) {
            attributes = _deep_merge(chef_solo_attributes, {'run_list' => fetch(:chef_solo_run_list, [])})
            to = File.join(chef_solo_path, 'config', 'solo.json')
            if chef_solo_host_attributes.empty?
              put(_json(attributes), to)
            else
              execute_on_servers { |servers|
                servers.each { |server|
                  host_attributes = _deep_merge(attributes, chef_solo_host_attributes.fetch(server.host, {}))
                  Capistrano::Transfer.process(:up, StringIO.new(_json(host_attributes)), to, [sessions[server]], :logger => logger)
                }
              }
            end
          }

          task(:invoke) {
            execute = []
            execute << "cd #{chef_solo_path}"
            execute << "#{sudo} #{bundle_cmd} exec chef-solo " + \
                         "-c #{File.join(chef_solo_path, 'config', 'solo.rb')} " + \
                         "-j #{File.join(chef_solo_path, 'config', 'solo.json')}"
            run(execute.join(' && '))
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::ChefSolo)
end

# vim:set ft=ruby ts=2 sw=2 :
