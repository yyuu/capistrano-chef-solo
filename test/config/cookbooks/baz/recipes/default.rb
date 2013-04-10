file "/tmp/baz" do
  owner "root"
  group "root"
  mode "0644"
  content data_bag_item("baz", "data")["value"]
end

# vim:set ft=ruby sw=2 ts=2 :
