#
# Cookbook Name:: ark
# Provider:: Ark
#
# Author:: Bryan W. Berry <bryan.berry@gmail.com>
# Author:: Sean OMeara <someara@opscode.com
# Copyright 2012, Bryan W. Berry
# Copyright 2013, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

use_inline_resources if Gem::Version.new(Chef::VERSION) >= Gem::Version.new('11')

# From resources/default.rb
# :install, :put, :dump, :cherry_pick, :install_with_make, :configure, :setup_py_build, :setup_py_install, :setup_py

# Used in test.rb
# :install, :put, :dump, :cherry_pick, :install_with_make, :configure

#################
# action :install
#################
action :install do
  set_paths

  directory new_resource.path do
    recursive true
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  remote_file new_resource.release_file do
    Chef::Log.debug("DEBUG: new_resource.release_file")
    source new_resource.url
    if new_resource.checksum then checksum new_resource.checksum end
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # unpack based on file extension
  execute "unpack #{new_resource.release_file}" do
    command unpack_command
    cwd new_resource.path
    environment new_resource.environment
    notifies :run, "execute[set owner on #{new_resource.path}]"
    action :nothing
  end

  # set_owner
  execute "set owner on #{new_resource.path}" do
    command "/bin/chown -R #{new_resource.owner}:#{new_resource.group} #{new_resource.path}"
    action :nothing
  end

  # symlink binaries
  new_resource.has_binaries.each do |bin|
    link ::File.join(new_resource.prefix_bin, ::File.basename(bin)) do
      to ::File.join(new_resource.path, bin)
    end
  end

  # action_link_paths
  link new_resource.home_dir do
    to new_resource.path
  end

  # Add to path for interactive bash sessions
  template "/etc/profile.d/#{new_resource.name}.sh" do
    source "add_to_path.sh.erb"
    owner "root"
    group "root"
    mode "0755"
    variables( :directory => "#{new_resource.path}/bin" )
    only_if { new_resource.append_env_path }
  end

  # Add to path for the current chef-client converge.
  bin_path = ::File.join(new_resource.path, 'bin')
  ruby_block "adding path to chef-client ENV['PATH']" do
    block do
      ENV['PATH'] = bin_path + ':' + ENV['PATH']
    end
    only_if{ ENV['PATH'].scan(bin_path).empty? }
  end
end


##############
# action :put
##############
action :put do
  set_put_paths

  directory new_resource.path do
    recursive true
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # download
  remote_file new_resource.release_file do
    source new_resource.url
    if new_resource.checksum then checksum new_resource.checksum end
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # unpack based on file extension
  execute "unpack #{new_resource.release_file}" do
    command unpack_command
    cwd new_resource.path
    environment new_resource.environment
    notifies :run, "execute[set owner on #{new_resource.path}]"
    action :nothing
  end

  # set_owner
  execute "set owner on #{new_resource.path}" do
    command "/bin/chown -R #{new_resource.owner}:#{new_resource.group} #{new_resource.path}"
    action :nothing
  end

  # symlink binaries
  new_resource.has_binaries.each do |bin|
    link ::File.join(new_resource.prefix_bin, ::File.basename(bin)) do
      to ::File.join(new_resource.path, ::File.basename(bin))
    end
  end

  # Add to path for interactive bash sessions
  template "/etc/profile.d/#{new_resource.name}.sh" do
    source "add_to_path.sh.erb"
    owner "root"
    group "root"
    mode "0755"
    variables( :directory => "#{new_resource.path}/bin" )
    only_if { new_resource.append_env_path }
  end
end

###########################
# action :dump
###########################
action :dump do
  set_dump_paths

  directory new_resource.path do
    recursive true
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # download
  remote_file new_resource.release_file do
    Chef::Log.debug("DEBUG: new_resource.release_file #{new_resource.release_file}")
    source new_resource.url
    if new_resource.checksum then checksum new_resource.checksum end
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # unpack based on file extension
  execute "unpack #{new_resource.release_file}" do
    command dump_command
    cwd new_resource.path
    environment new_resource.environment
    notifies :run, "execute[set owner on #{new_resource.path}]"
    action :nothing
  end

  # set_owner
  execute "set owner on #{new_resource.path}" do
    command "/bin/chown -R #{new_resource.owner}:#{new_resource.group} #{new_resource.path}"
    action :nothing
  end
end

#####################
# action :cherry_pick
#####################
action :cherry_pick do
  set_cherry_pick_paths

  directory new_resource.path do
    recursive true
    action :create
    notifies :create, "ruby_block[cherry_pick files]"
  end

  # download
  remote_file new_resource.release_file do
    source new_resource.url
    if new_resource.checksum then checksum new_resource.checksum end
    action :create
    notifies :create, "ruby_block[cherry_pick files]"
  end

  ruby_block "cherry_pick files" do
    block do
      Array(new_resource.files).each do |file|
        file_path = ::File.join(new_resource.path, ::File.basename(file))

        # extract file
        c = Chef::Resource::Execute.new("cherry_pick #{file} from #{new_resource.release_file}", run_context)
        Chef::Log.debug("DEBUG: unpack_type: #{unpack_type}")
        c.command cherry_pick_command(file)
        c.creates file_path
        c.run_action(:run)

        # set_owner
        f = Chef::Resource::File.new("set owner on #{file}", run_context)
        f.path file_path
        f.owner new_resource.owner
        f.group new_resource.group
        f.mode new_resource.mode
        f.run_action(:create)
      end
    end
    action :nothing
  end
end


###########################
# action :install_with_make
###########################
action :install_with_make do
  set_paths

  directory new_resource.path do
    recursive true
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  remote_file new_resource.release_file do
    Chef::Log.debug("DEBUG: new_resource.release_file")
    source new_resource.url
    if new_resource.checksum then checksum new_resource.checksum end
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # unpack based on file extension
  execute "unpack #{new_resource.release_file}" do
    command unpack_command
    cwd new_resource.path
    environment new_resource.environment
    notifies :run, "execute[autogen #{new_resource.path}]"
    notifies :run, "execute[configure #{new_resource.path}]"
    notifies :run, "execute[make #{new_resource.path}]"
    notifies :run, "execute[make install #{new_resource.path}]"
    action :nothing
  end

  execute "autogen #{new_resource.path}" do
    command "./autogen.sh"
    only_if "test -f ./autogen.sh"
    cwd new_resource.path
    environment new_resource.environment
    action :nothing
    ignore_failure true
  end

  execute "configure #{new_resource.path}" do
    command "./configure #{new_resource.autoconf_opts.join(' ')}"
    only_if "test -f ./configure"
    cwd new_resource.path
    environment new_resource.environment
    action :nothing
  end

  execute "make #{new_resource.path}" do
    command "make #{new_resource.make_opts.join(' ')}"
    cwd new_resource.path
    environment new_resource.environment
    action :nothing
  end

  execute "make install #{new_resource.path}" do
    command "make install #{new_resource.make_opts.join(' ')}"
    cwd new_resource.path
    environment new_resource.environment
    action :nothing
  end
end

action :configure do
  set_paths

  directory new_resource.path do
    recursive true
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  remote_file new_resource.release_file do
    Chef::Log.debug("DEBUG: new_resource.release_file")
    source new_resource.url
    if new_resource.checksum then checksum new_resource.checksum end
    action :create
    notifies :run, "execute[unpack #{new_resource.release_file}]"
  end

  # unpack based on file extension
  execute "unpack #{new_resource.release_file}" do
    command unpack_command
    cwd new_resource.path
    environment new_resource.environment
    notifies :run, "execute[autogen #{new_resource.path}]"
    notifies :run, "execute[configure #{new_resource.path}]"
    action :nothing
  end

  execute "autogen #{new_resource.path}" do
    command "./autogen.sh"
    only_if "test -f ./autogen.sh"
    cwd new_resource.path
    environment new_resource.environment
    action :nothing
    ignore_failure true
  end

  execute "configure #{new_resource.path}" do
    command "./configure #{new_resource.autoconf_opts.join(' ')}"
    only_if "test -f ./configure"
    cwd new_resource.path
    environment new_resource.environment
    action :nothing
  end
end
