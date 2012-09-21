# capistrano-chef-solo

a capistrano recipe to invoke `chef-solo`.

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-chef-solo'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-chef-solo

## Usage

This recipe will try to bootstrap your servers with `chef-solo`. Following processes will be invoked.

1. Install ruby for `chef-solo` with [capistrano-rbenv](https://github.com/yyuu/capistrano-rbenv)
2. Install `chef` with [bundler](http://gembundler.com)
3. Checkout your cookbooks and configurations
4. Invoke `chef-solo`

To setup your servers with `chef-solo`, add following in you `config/deploy.rb`.

    # in "config/deploy.rb"
    require 'capistrano-chef-solo'
    set(:chef_solo_cookbook_repository, "git@example.com:foo/bar.git")

And then, now you can start `chef-solo` via capistrano.

    $ cap chef-solo

Following options are available to manage your `chef-solo`.

 * `:chef_solo_version` - the version of chef.
 * `:chef_solo_user` - special user to invoke `chef-solo`. use `user` by default.
 * `:chef_solo_ssh_options` - special ssh options for `chef_solo_user`. use `ssh_options` by default.
 * `:chef_solo_ruby_version` - ruby version to launch `chef-solo`.
 * `:chef_solo_cookbook_repository` - the URL of your cookbook repository.
 * `:chef_solo_cookbook_revision` - the `branch` in the repository.
 * `:chef_solo_attributes` - the `attributes` to apply to `chef-solo`.
 * `:chef_solo_run_list` - the `run_list` to apply to `chef-solo`.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
