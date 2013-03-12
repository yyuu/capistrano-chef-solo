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


## Examples

### Using cookbooks

#### Using cookbooks from local path

By default, `capistrano-chef-solo` searches cookbooks from local path of `config/cookbooks`.
You can specify the cookbooks directory with using `chef_solo_cookbooks_subdir`.

    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_subdir, "config/cookbooks")

#### Using cookbooks from remote repository

You can use cookbooks in remote repository.

    set(:chef_solo_cookbooks_scm, :git)
    set(:chef_solo_cookbooks_repository, "git://example.com/example.git")
    set(:chef_solo_cookbooks_revision, "master")
    set(:chef_solo_cookbooks_subdir, "/")

#### Using mixed configuration

You can use multiple cookbooks repositories at once.

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


### Attributes configuration

#### Setting common attributes

To apply same attributes to all hosts.

    set(:chef_solo_attributes) {{
      "locales" => { "language" => "ja" },
      "tzdata" => { "timezone" => "Asia/Tokyo" },
    }}
    set(:chef_solo_run_list, ["recipe[locales]", "recipe[tzdata]"])

#### Setting individual attributes per roles

In some cases, you may want to apply individual `attributes` per roles.

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

#### Setting individual attributes per host

In some cases, you may want to apply individual `attributes` per hosts.
(Something like `server_id` of mysqld or VRRP priority of keepalived)

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


## Reference

Following options are available to manage your `chef-solo`.

 * `:chef_solo_version` - the version of chef.
 * `:chef_solo_cookbooks` - the definition of cookbooks. by default, copy cookbooks from `./config/cookbooks`.
 * `:chef_solo_attributes` - the `attributes` of chef-solo. must be a `Hash<String,String>`. will be converted into JSON.
 * `:chef_solo_run_list` - the `run_list` of chef-solo. must be an `Array<String>`. will be merged into `:chef_solo_attributes`.
 * `:chef_solo_role_attributes` - per-role `attributes` of chef-solo. must be a `Hash<String,Hash<String,String>>`.
 * `:chef_solo_role_run_list` - per-role `run_list` of chef-solo. must be a `Hash<String,Array<String>>`.
 * `:chef_solo_host_attributes` - per-host `attributes` of chef-solo. must be a `Hash<String,Hash<String,String>>`.
 * `:chef_solo_host_run_list` - per-host `run_list` of chef-solo. must be a `Hash<String,Array<String>>`.

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
