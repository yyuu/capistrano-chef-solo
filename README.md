# capistrano-chef-solo

a capistrano recipe to invoke `chef-solo`.

## Installation

Add this line to your application's Gemfile:

    gem 'yyuu-capistrano-chef-solo'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install yyuu-capistrano-chef-solo

## Usage

This recipe will try to bootstrap your servers with `chef-solo`. Following processes will be invoked.

1. Install ruby with using [capistrano-rbenv](https://github.com/yyuu/capistrano-rbenv)
2. Install `chef` with using [bundler](http://gembundler.com)
3. Checkout your cookbooks
4. Generate `attributes` and `run_list` for your hosts
5. Invoke `chef-solo`

To setup your servers with `chef-solo`, add following in you `config/deploy.rb`.

    # in "config/deploy.rb"
    require "capistrano-chef-solo"
    set(:chef_solo_version, "11.4.0")

And then, now you can start using `chef-solo` via Capistrano.
This task will deploy cookbooks from `./config/cookbooks`, and then invoke `chef-solo`.

    $ cap chef-solo

Plus, there is special method `chef_solo.run_list`. You can use this to apply recipes during deployment.

    after "deploy:finalize_update" do
      chef_solo.run_list "recipe[foo]", "recipe[bar]", "recipe[baz]"
    end

### Bootstrap mode

After the first time of boot up of servers, you might need to apply some recipes for your initial setup.
Let us say you want to have two users on servers.

* admin - the default user of system, created by system installer. use this for bootstrap. can invoke all commands via sudo.
* deploy - the user to use for application deployments. will be created during bootstrap. can invoke all commands via sudo.

There is _bootstrap_ mode for this kind of situations.
To setup these users, set them in your Capfile.

    ~~~ ruby
    set(:user, "deploy")
    set(:chef_solo_bootstrap_user, "admin")
    ~~~

Then, apply recipes with _bootstrap_ mode.

    % cap -S chef_solo_bootstrap=true chef-solo

After the bootstrap, you can deploy application normaly with `deploy` user.

    % cap deploy:setup


## Examples

### Using cookbooks

#### Using cookbooks from local path

By default, `capistrano-chef-solo` searches cookbooks from local path of `config/cookbooks`.
You can specify the cookbooks directory with using `chef_solo_cookbooks_subdir`.

    ~~~ ruby
    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_subdir, "config/cookbooks")
    ~~~

#### Using cookbooks from remote repository

You can use cookbooks in remote repository.

    ~~~ ruby
    set(:chef_solo_cookbooks_scm, :git)
    set(:chef_solo_cookbooks_repository, "git://example.com/example.git")
    set(:chef_solo_cookbooks_revision, "master")
    set(:chef_solo_cookbooks_subdir, "/")
    ~~~

#### Using mixed configuration

You can use multiple cookbooks repositories at once.

    ~~~ ruby
    set(:chef_solo_cookbooks) {{
      # use cookbooks in ./config/cookbooks.
      "local" => {
        :scm => :none,
        :cookbooks => "config/cookbooks",
      },
      # use cookbooks in git repository.
      "repository" => {
        :scm => :git,
        :repository => "git://example.com/example.git",
        :revision => "master",
        :cookbooks => "/",
      }
    }}
    ~~~


### Attributes configuration

By default, the Chef attributes will be generated by following order.

1. Use _non-lazy_ variables of Capistrano.
2. Use attributes defined in `:chef_solo_attributes`.
3. Use attributes defined in `:chef_solo_role_attributes` for target role.
4. Use attributes defined in `:chef_solo_host_attributes` for target host.

#### Setting common attributes

To apply same attributes to all hosts.

    ~~~ ruby
    set(:chef_solo_attributes) {{
      "locales" => { "language" => "ja" },
      "tzdata" => { "timezone" => "Asia/Tokyo" },
    }}
    set(:chef_solo_run_list, ["recipe[locales]", "recipe[tzdata]"])
    ~~~

#### Setting individual attributes per roles

In some cases, you may want to apply individual `attributes` per roles.

    ~~~ ruby
    set(:chef_solo_role_attributes) {
      :app => {
        "foo" => "foo",
      },
      :web => {
        "bar" => "bar",
      },
    }
    set(:chef_solo_role_run_list) {
      :app => ["recipe[build-essential]"],
    }
    ~~~

#### Setting individual attributes per host

In some cases, you may want to apply individual `attributes` per hosts.
(Something like `server_id` of mysqld or VRRP priority of keepalived)

    ~~~ ruby
    set(:chef_solo_host_attributes) {
      "foo1.example.com" => {
        "keepalived" => {
          "virtual_router_id" => 1,
          "priority" => 100, #=> MASTER
          "virtual_ipaddress" => "192.168.0.1/24",
        },
      },
      "foo2.example.com" => {
        "keepalived" => {
          "virtual_router_id" => 1,
          "priority" => 50, #=> BACKUP
          "virtual_ipaddress" => "192.168.0.1/24",
        },
      },
    }
    ~~~

#### Testing attributes

You can check generated attributes with using `chef-solo:attributes` task.

    % cap HOST=foo.example.com chef-solo:attributes


## Reference

Following options are available to manage your `chef-solo`.

 * `:chef_solo_version` - the version of chef.
 * `:chef_solo_cookbooks` - the definition of cookbooks. by default, copy cookbooks from `./config/cookbooks`.
 * `:chef_solo_attributes` - the `attributes` of chef-solo. must be a `Hash<String,String>`. will be converted into JSON.
 * `:chef_solo_run_list` - the `run_list` of chef-solo. must be an `Array<String>`. will be merged into `:chef_solo_attributes`.
 * `:chef_solo_role_attributes` - the per-roles `attributes` of chef-solo. must be a `Hash<Symbol,Hash<String,String>>`.
 * `:chef_solo_role_run_list` - the per-roles `run_list` of chef-solo. must be a `Hash<Symbol,Array<String>>`.
 * `:chef_solo_host_attributes` - the per-hosts `attributes` of chef-solo. must be a `Hash<String,Hash<String,String>>`.
 * `:chef_solo_host_run_list` - the per-hosts `run_list` of chef-solo. must be a `Hash<String,Array<String>>`.
 * `:chef_solo_capistrano_attributes` - the Capistrano variables to use as Chef attributes.
 * `:chef_solo_capistrano_attributes_exclude` - the black list for `:chef_solo_capistrano_attributes`
 * `:chef_solo_capistrano_attributes_include` - the white list for `:chef_solo_capistrano_attributes`


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
