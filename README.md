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

1. Install ruby for `chef-solo` with [capistrano-rbenv](https://github.com/yyuu/capistrano-rbenv)
2. Install `chef` with [bundler](http://gembundler.com)
3. Checkout your cookbooks and configurations
4. Invoke `chef-solo`

To setup your servers with `chef-solo`, add following in you `config/deploy.rb`.

    # in "config/deploy.rb"
    require "capistrano-chef-solo"
    set(:chef_solo_version, "11.4.0")
    set(:chef_solo_cookbooks_scm, :none)
    set(:chef_solo_cookbooks_subdir, "config/cookbooks")

And then, now you can start using `chef-solo` via capistrano.

    $ cap chef-solo

Following options are available to manage your `chef-solo`.

 * `:chef_solo_version` - the version of chef.
 * `:chef_solo_cookbooks` - the definition of cookbooks. you can set multiple repositories from here.
 * `:chef_solo_attributes` - the `attributes` of chef-solo. must be a `Hash<String,String>`. will be converted into JSON.
 * `:chef_solo_run_list` - the `run_list` of chef-solo. must be an `Array<String>`. will be merged into `:chef_solo_attributes`.
 * `:chef_solo_role_attributes` - per-role `attributes` of chef-solo. must be a `Hash<String,Hash<String,String>>`.
 * `:chef_solo_role_run_list` - per-role `run_list` of chef-solo. must be a `Hash<String,Array<String>>`.
 * `:chef_solo_host_attributes` - per-host `attributes` of chef-solo. must be a `Hash<String,Hash<String,String>>`.
 * `:chef_solo_host_run_list` - per-host `run_list` of chef-solo. must be a `Hash<String,Array<String>>`.

## Examples

### Setting `attributes` and `run_list`

To apply some `attributes` to your hosts, set something like following in your `config/deploy.rb` or so.

    set(:chef_solo_attributes) {{
      "locales" => { "language" => "ja" },
      "tzdata" => { "timezone" => "Asia/Tokyo" },
    }}
    set(:chef_solo_run_list, ["recipe[build-essential]", "recipe[locales]", "recipe[tzdata]"])

### Setting individual `attributes` and `run_list` per host

In some cases, you may want to apply individual `attributes` per host.
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
