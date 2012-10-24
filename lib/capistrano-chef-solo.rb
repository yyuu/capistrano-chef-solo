require 'capistrano-chef-solo/version'
require 'capistrano-rbenv'
require 'capistrano/configuration'
require 'capistrano/recipes/deploy/scm'
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
          _cset(:chef_solo_version, '0.10.12')
          _cset(:chef_solo_path) { File.join(chef_solo_home, 'chef') }
          _cset(:chef_solo_path_children, %w(bundle cache config cookbooks))

          desc("Run chef-solo.")
          task(:default) {
            # login as chef user if specified
            set(:user, fetch(:chef_solo_user, user))
            set(:ssh_options, fetch(:chef_solo_ssh_options, ssh_options))

            transaction {
              bootstrap
              update
            }
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
            remote_tmpdir = Dir.mktmpdir()
            destination = File.join(tmpdir, 'cookbooks')
            remote_destination = File.join(chef_solo_path, 'cookbooks')
            filename = File.join(tmpdir, 'cookbooks.tar.gz')
            remote_filename = File.join(remote_tmpdir, 'cookbooks.tar.gz')
            begin
              bundle_cookbooks(filename, destination)
              run("mkdir -p #{remote_tmpdir}")
              distribute_cookbooks(filename, remote_filename, remote_destination)
            ensure
              run("rm -rf #{remote_tmpdir}")
              run_locally("rm -rf #{tmpdir}")
            end
          }

          _cset(:chef_solo_cookbook_repository) { abort("chef_solo_cookbook_repository not set") }
          _cset(:chef_solo_cookbooks_repository) {
            logger.info("WARNING: `chef_solo_cookbook_repository' has been deprecated. use `chef_solo_cookbooks_repository' instead.")
            chef_solo_cookbook_repository
          }
          _cset(:chef_solo_cookbook_revision, 'HEAD')
          _cset(:chef_solo_cookbooks_revision) {
            logger.info("WARNING: `chef_solo_cookbook_revision' has been deprecated. use `chef_solo_cookbooks_revision' instead.")
            chef_solo_cookbook_revision
          }
          _cset(:chef_solo_cookbook_subdir, '/')
          _cset(:chef_solo_cookbooks_subdir) {
            logger.info("WARNING: `chef_solo_cookbook_subdir' has been deprecated. use `chef_solo_cookbooks_subdir' instead.")
            chef_solo_cookbook_subdir
          }
          _cset(:chef_solo_cookbooks_exclude, [])

          # special variable to set multiple cookbooks repositories.
          # by default, it will build from :chef_solo_cookbooks_* variables.
          _cset(:chef_solo_cookbooks) {
            name = File.basename(chef_solo_cookbooks_repository, File.extname(chef_solo_cookbooks_repository))
            {
              name => {
                :repository => chef_solo_cookbooks_repository,
                :revision => chef_solo_cookbooks_revision,
                :cookbooks => chef_solo_cookbooks_subdir,
                :cookbooks_exclude => chef_solo_cookbooks_exclude,
              }
            }
          }

          _cset(:chef_solo_configuration, configuration)
          _cset(:chef_solo_repository_cache) { File.expand_path('./tmp/cookbooks-cache') }
          def bundle_cookbooks(filename, destination)
            dirs = [ File.dirname(filename), destination ].uniq
            run_locally("mkdir -p #{dirs.join(' ')}")
            chef_solo_cookbooks.each do |name, options|
              configuration = Capistrano::Configuration.new()
              chef_solo_configuration.variables.merge(options).each { |key, val|
                configuration.set(key, val)
              }
              # refreshing just :source, :revision and :real_revision is enough?
              configuration.set(:source) { Capistrano::Deploy::SCM.new(configuration[:scm], configuration) }
              configuration.set(:revision) { configuration[:source].head }
              configuration.set(:real_revision) {
                configuration[:source].local.query_revision(configuration[:revision]) { |cmd|
                  with_env("LC_ALL", "C") { run_locally(cmd) }
                }
              }
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

          _cset(:chef_solo_attributes, {})
          task(:update_attributes) {
            attributes = chef_solo_attributes.merge('run_list' => fetch(:chef_solo_run_list, []))
            put(attributes.to_json, File.join(chef_solo_path, 'config', 'solo.json'))
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
