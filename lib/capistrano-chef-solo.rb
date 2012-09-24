require "capistrano-chef-solo/version"
require 'capistrano-rbenv'
require 'json'
require 'tmpdir'

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
            update_cookbook
            update_config
            update_attributes
            invoke
          }

          _cset(:chef_solo_cookbook_repository) {
            abort("chef_solo_cookbook_repository not set")
          }
          _cset(:chef_solo_cookbook_revision, 'HEAD')
          task(:update_cookbook) {
            git = fetch(:chef_solo_git, 'git')
            tar = fetch(:chef_solo_tar, 'tar')
            copy_dir = Dir.mktmpdir()
            destination = File.join(copy_dir, 'cookbooks')
            filename = "#{destination}.tar.gz"
            remote_destination = File.join(chef_solo_path, 'cookbooks')
            remote_filename = File.join('/tmp', File.basename(filename))

            begin
              checkout = []
              checkout << "#{git} clone -q #{chef_solo_cookbook_repository} #{destination}"
              checkout << "cd #{destination} && #{git} checkout -q -b deploy #{chef_solo_cookbook_revision}"
              run_locally(checkout.join(' && '))

              copy = []
              copy << "cd #{File.dirname(destination)} && #{tar} chzf #{filename}  #{File.basename(destination)}"
              run_locally(copy.join(' && '))

              upload(filename, remote_filename)
              run("cd #{File.dirname(remote_destination)} && #{tar} xzf #{remote_filename} && rm -f #{remote_filename}")
            ensure
              run_locally("rm -rf #{copy_dir}")
            end
          }

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
