v0.1.0 (Yamashita, Yuu)

* Deploy cookbooks from local `./config/cookbooks` by default. Also you can still deploy them from external SCM with some extra configuration.
* Update default Chef version (10.16.4 -> 11.4.0)
* Add `chef_solo.run_list()` method like [roundsman](https://github.com/iain/roundsman).
* Add `chef_solo:attributes` task to debug attributes.
* Replace old style `:chef_solo_user` by _bootstrap_ mode.
* Call `bundle install` to install Chef only if the Chef has not been installed.

v0.1.1 (Yamashita, Yuu)

* Set `:rbenv_setup_default_environment` as `false` to avoid the problem with _bootstrap_ mode. 

v0.1.2 (Yamashita, Yuu)

* Deploy cookbooks with using deploy strategies of Capistrano. Use [copy_subdir](https://github.com/yyuu/capistrano-copy-subdir) strategy by default.

v0.1.3 (Yamashita, Yuu)

* Add support for deploying single cookbook repositories (like cookbooks in https://github.com/opscode-cookbooks).

v0.1.4 (Yamashita, Yuu)

* Add support for data bags of Chef. By default, deploy data bags from local `./config/data_bags`.
* Add `:chef_solo_use_bundler` parameter. Try to install Chef without using Bundler if set `false`.
* Add `chef_solo:purge` task to uninstall Chef.

v0.1.5 (Yamashita, Yuu)

* Catch exceptions on initial handshake during bootstrap mode.
* Improve error logging during bootstrap mode.
* Support regex match for `:chef_solo_capistrano_attributes_exclude` and `:chef_solo_capistrano_attributes_include`.

v0.1.6 (Yamashita, Yuu)

* Support options Hash in `chef_solo.run_list()`. Now it skips updating cookbooks, data bags, attirbutes and configurations if `:update => false` was given.
