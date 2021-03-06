#----
# Set up preseeding data for debian packages
#---
directory '/var/cache/local/preseeding' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
end

template '/var/cache/local/preseeding/mysql-server.seed' do
  source 'mysql-server.seed.erb'
  owner 'root'
  group 'root'
  mode '0600'
  notifies :run, 'execute[preseed mysql-server]', :immediately
end

execute 'preseed mysql-server' do
  command '/usr/bin/debconf-set-selections /var/cache/local/preseeding/mysql-server.seed'
  action  :nothing
end

#----
# Install software
#----
node['mysql']['server']['packages'].each do |name|
  package name do
    action :install
  end
end

node['mysql']['server']['directories'].each do |key, value|
  directory value do
    owner     'mysql'
    group     'mysql'
    mode      '0775'
    action    :create
    recursive true
  end
end

#----
# Grants
#----
template '/etc/mysql_grants.sql' do
  source 'grants.sql.erb'
  owner  'root'
  group  'root'
  mode   '0600'
  notifies :run, 'execute[install-grants]', :immediately
end

cmd = install_grants_cmd
execute 'install-grants' do
  command cmd
  action :nothing
end

template '/etc/mysql/debian.cnf' do
  source 'debian.cnf.erb'
  owner 'root'
  group 'root'
  mode '0600'
  notifies :reload, 'service[mysql]'
end

#----
# data_dir
#----

# DRAGONS!
# Setting up data_dir will only work on initial node converge...
# Data will NOT be moved around the filesystem when you change data_dir
# To do that, we'll need to stash the data_dir of the last chef-client
# run somewhere and read it. Implementing that will come in "The Future"

directory node['mysql']['data_dir'] do
  owner     'mysql'
  group     'mysql'
  action    :create
  recursive true
end

template '/etc/init/mysql.conf' do
  source 'init-mysql.conf.erb'
  only_if { node['platform'] == 'ubuntu' }
end

template '/etc/apparmor.d/usr.sbin.mysqld' do
  source 'usr.sbin.mysqld.erb'
  action :create
  notifies :reload, 'service[apparmor-mysql]', :immediately
end

service 'apparmor-mysql' do
  service_name 'apparmor'
  action :nothing
  supports :reload => true
end

template '/etc/mysql/my.cnf' do
  source 'my.cnf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :run, 'bash[move mysql data to datadir]', :immediately
  notifies :reload, 'service[mysql]'
end

# don't try this at home
# http://ubuntuforums.org/showthread.php?t=804126
bash 'move mysql data to datadir' do
  user 'root'
  code <<-EOH
  /usr/sbin/service mysql stop &&
  mv /var/lib/mysql/* #{node['mysql']['data_dir']} &&
  /usr/sbin/service mysql start
  EOH
  action :nothing
  only_if "[ '/var/lib/mysql' != #{node['mysql']['data_dir']} ]"
  only_if "[ `stat -c %h #{node['mysql']['data_dir']}` -eq 2 ]"
  not_if '[ `stat -c %h /var/lib/mysql/` -eq 2 ]'
end

#######################################To create Database
#mysql_database node['mysql']['database'] do
# connection ({:host => 'localhost', :username => 'root', :password => node['mysql']['server_root_password']})
# action :create
#end
#
#mysql_database_user node['mysql']['db_username'] do
#  connection ({:host => 'localhost', :username => 'root', :password => node['mysql']['server_root_password']})
#  password node['mysql']['db_password']
#  database_name node['mysql']['database']
#  host '%'
#  privileges [:all]
#  action :grant
#end
#
#######################################################
service_provider = Chef::Provider::Service::Upstart if 'ubuntu' == node['platform'] &&
  Chef::VersionConstraint.new('>= 13.10').include?(node['platform_version'])


service 'mysql' do
  provider service_provider
  service_name 'mysql'
  supports     :status => true , :restart => true, :reload => true
  action       [:enable, :start]
end


#____________________________________________________________-------------------------------------------------------***********


#mysql_database node['mysql']['database'] do
 # connection ({:host => 'localhost', :username => 'root', :password => node['mysql']['server_root_password']})
 # action :create
#end

#mysql_database_user node['mysql']['db_username'] do
#  connection ({:host => 'localhost', :username => 'root', :password => node['mysql']['server_root_password']})
#  password node['mysql']['db_password']
#  database_name node['mysql']['database']
 # privileges [:select,:update,:insert,:create,:delete]
#  action :grant
#end

##########################################################
