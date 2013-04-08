file "/tmp/two" do
  owner "root"
  group "root"
  mode "0644"
  content data_bag_item("two", "data")["value"]
end

# vim:set ft=ruby sw=2 ts=2 :
