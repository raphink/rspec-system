# rspec-system

`rspec-system` provides a framework for creating system tests using the `rspec` testing library.

The goal here is to provide facilities to aid in the launching of tests nodes, copying of test content to such nodes, and executing commands on such nodes to be tested with standard rspec assertions within the standard rspec test format.

*Note:* This library is fairly alpha at the moment, and the interface may change at without warning. That said, if you're good at ruby and have an opinion, I'd appreciate patches and improvements to move this further torwards stability.

### Gem installation

The intention is that this gem is used within your project as a development library.

Either install `rspec-system` manually with:

    gem install rspec-system

However it is usually recommended to include it in your `Gemfile` and let bundler install it, by adding the following:

    gem 'rspec-system'

Then installing with:

    bundle install

### Writing tests

Start by creating a helper file in `spec/spec_helper_system.rb` containing something like the following:

    require 'rspec-system/spec_helper'

    RSpec.configure do |c|
      c.system_setup_block = proc do
        include RSpecSystem::Helpers
        # Insert some setup tasks here
        system_run('yum install -y ntp')
      end
    end

Create the directory `spec/system` in your project, make sure your unit tests go into `spec/unit` or somesuch so you can isolate them easily during test time. Add files with the spec prefix ie. `mytests_spec.rb` and make sure they always include the line `require 'spec_helper_system'` eg.:

    require 'spec_helper_system'

    describe 'basics' do
      it 'should cat /etc/resolv.conf' do
        system_run('cat /etc/resolv.conf') do |r|
          r[:stdout].should =~ /localhost/
        end
      end
    end

Also consult the example in `example` in the source of this library for more details.

For you reference, here are the list of custom rspec configuration items that can be overriden in your `spec_helper_system.rb` file:

* *system_setup_block* - this accepts a proc that is called after node setup, but before every test (ie. before suite). The goal of this option is to provide a good place for node setup independant of tests.
* *system_tmp* - For some of our activity, we require a temporary file area. By default we just a random temporary path, so you normally do not need to set this.

Currently to get the nice formatting rspec-system specific formatter its recommended to use the Rake task, so the following to your `Rakefile`:

    require 'rspec-system/rake_task'

That will setup the rake task `rake spec:system`.

### Creating a nodeset file

A nodeset file outlines all the node configurations for your tests. The concept here is to define one or more 'nodesets' each nodeset containing one or more 'nodes'. Create the file in your projects root directory as `.nodeset.yml`.

    ---
    default_set: 'centos-58-x64'
    sets:
      'centos-58-x64':
        nodes:
          'main.vm':
            prefab: 'centos-58-x64'
      'debian-606-x64':
        nodes:
          'main.vm':
            prefab: 'debian-606-x64'

The file must adhere to the Kwalify schema supplied in `resources/kwalify-schemas/nodeset_schema.yml`.

* `sets`: Each set contains a series of nodes, and is given a unique name. You can create sets with only 1 node if you like.
* `sets -> [setname] -> nodes`: Node definitions for a set. Each node needs a unique name so you can address each one individualy if you like.
* `sets -> [setname] -> nodes -> [name] -> prefab`: This relates to the prefabricated node template you wish to use. Currently this is the only way to launch a node. Look in `resources/prefabs.yml` for more details.
* `default_set`: this is the default set to run if none are provided with `rake spec:system`. This should be the most common platform normally.

### Prefabs

Prefabs are 'pre-rolled' virtual images, for now its the only way to specify a template. In the future we will probably allow you to specify your own prefab file, and override prefab settings in a nodeset file as well.

The current built-in prefabs are defined in `resources/prefabs.yml`. The current set are based on boxes hosted on <http://puppet-vagrant-boxes.puppetlabs.com> as they have been built by myself and are generally trusted and have a reproducable build cycle (they aren't just 'golden images'). In the future I'll probably expand that list, but attempt to stick to boxes that we have control over.

Prefabs are designed to be generic across different hosting environments. For example, you should be able to use a prefab string and launch an EC2 or Vagrant image and find that the images are identical (or as much as possible). The goal should be that local Vagrant users should find their own local tests pass, and when submitting code this should not change for EC2.

For this reason there are various `provider_specific` settings that apply to different provider types. For now though, only `vagrant` specific settings are provided.

`facts` in the prefab are literally dumps of `facter -p` on the host stored in the prefab file so you can look them up without addressing the machine. These are accessed using the `system_node#facts` method on the helper results and can be used in conditional logic during test runs and setup tasks. Not all the facts are supplied, only the more interesting ones.

### Running tests

Run the system tests with:

    rake spec:system

Instead of switches, we use a number of environment variables to modify the behaviour of running tests. This is more inline with the way testing frameworks like Jenkins work, and should be pretty easy for command line users as well:

* *RSPEC_VIRTUAL_ENV* - the type of virtual environment to run (currently `vagrant` is the only option). I'm undecided about this variable, so assume it might change in the future.
* *RSPEC_SET* - the set to use when running tests (defaults to the `default_set` setting in the projects `.nodeset.yml` file). This string must align with the entries under `sets` in your `.nodeset.yml`.

So if you wanted to run an alternate nodeset you could use:

    RSPEC_SET=nodeset2 rake spec:system

In Jenkins you should be able to use RSPEC\_SET in a test matrix, thus obtaining quite a nice integration and visual display of nodesets in Jenkins.

### Plugins to rspec-system

Right now we have two types of plugins, the framework is in a state of flux as to how one writes these things but here we go.

#### Helper libraries

Libraries that provide test helpers, and setup helpers for testing development on the software in question.

* rspec-system-puppet <http://rubygems.org/gems/rspec-system-puppet>

#### Node providers

A node provider should provide the ability to launch nodes (or if they are already launched provide information to get to them), run commands on nodes, transfer files and shutdown nodes.

That is, abstractions around other virtualisation, cloud or system tools. Right now we only have one of these for Vagrant using VirtualBox specifically and its in core.

#### The Future of Plugins

I want to start an eco-system of plugins for rspec-system, but do it in a sane way. Right now I see the following potential plugin types, if you think you can help please do:

* node providers - that is, abstractions around other virtualisation, cloud or system tools. Right now a NodeSet is tied to a virtual type, but I think this isn't granual enough. Some ideas for future providers are:
    * blimpy - for firing up EC2 and OpenStack nodes, useful for Jenkins integration
    * vmware vsphere - for those who have VMWare vSphere deployed already, this would be an awesome bonus.
    * razor - for launching bare metail nodes for testing purposes. Could be really useful to have baremetal tests for software that needs it like `facter`.
    * manual - not everything has to be 'launched' I can see a need for defining a static configuration for older machines that can't be poked and peeked. Of course, we might need to add cleanup tasks for this case.
* helper libraries - libraries that provide test helpers, and setup helpers for testing development on the software in question.
    * distro - helpers that wrap common linux distro tasks, like package installation.
    * mcollective - for launching the basics, activemq, broker clusters. Useful for testing mcollective agents.
    * puppetdb - helpers for setting up puppetdb, probably using the modules we already have.
    * other config management tools - for the purposes of testing modules against them, or using them for test setup provisioners like I've mentioned before with Puppet.
    * others I'm sure ...

These could be shipped as external gems, and plugged in to the rspec-system framework somehow. Ideas on how to do this properly are very welcome, if you bring code as well :-).

### CI Integration

So currently I've only integrated this with Jenkins. If you have luck doing it on other CI platforms, feel free to add to this documentation.

#### Jenkins

My setup was:

* Single box - 32GB of RAM and 8 cpus
* Debian 7
* Jenkins 1.510 (installed via packages from the jenkins repos)
* Vagrant 1.1.5 (installed via packages from the vagrant site)
* VirtualBox 4.2.10 (installed via packages from virtualbox)
* RVM with Ruby 2.0.0

The setup for a job is basically:

* Setup your slave box to only have 1 executor (there is some bug here, something to do with vagrant not liking multiple projects)
* Create new matrix build
* Specify VCS settings etc. as per normal
* Create a user defined axis called 'RSPEC_SET' and add your nodesets in there: fedora-18-x64, centos-64-x64 etc.
* Use touchstone with a filter of RSPEC_SET=='centos-64-x64' so you don't chew up cycles running a whole batch of broken builds
* Create an execute shell job like so:

    #!/bin/bash
    set +e

    [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
    rvm use ruby-2.0.0@some_unique_name_here --create

    bundle update
    rake spec:system

I went quite complex and had Github pull request integration working with this, and quite a few other nice features. If you need help setting it up get in touch.
