require 'fileutils'
require 'systemu'
require 'net/ssh'

module RSpecSystem
  # A NodeSet implementation for Vagrant.
  class NodeSet::Vagrant < RSpecSystem::NodeSet::Base
    include RSpecSystem::Log

    ENV_TYPE = 'vagrant'

    # Creates a new instance of RSpecSystem::NodeSet::Vagrant
    #
    # @param setname [String] name of the set to instantiate
    # @param config [Hash] nodeset configuration hash
    def initialize(setname, config)
      super
      @vagrant_path = File.expand_path(File.join(RSpec.configuration.system_tmp, 'vagrant_projects', setname))
    end

    # Setup the NodeSet by starting all nodes.
    #
    # @return [void]
    def setup
      log.info "[Vagrant#setup] Begin setting up vagrant"

      create_vagrantfile()

      teardown()

      log.info "[Vagrant#setup] Running 'vagrant up'"
      vagrant("up")

      # Establish ssh connectivity
      ssh_channels = {}
      nodes.each do |k,v|
        log.info "[Vagrant#setup] establishing Net::SSH channel with #{k}"
        chan = Net::SSH.start(k, 'vagrant', :config => ssh_config)
        ssh_channels[k] = chan
      end
      RSpec.configuration.ssh_channels = ssh_channels

      nil
    end

    # Shutdown the NodeSet by shutting down or pausing all nodes.
    #
    # @return [void]
    def teardown
      log.info "[Vagrant#teardown] closing all ssh channels"
      RSpec.configuration.ssh_channels.each do |k,v|
        v.close unless v.closed?
      end

      log.info "[Vagrant#teardown] Running 'vagrant destroy'"
      vagrant("destroy --force")
      nil
    end

    # Run a command on a host in the NodeSet.
    #
    # @param opts [Hash] options
    # @return [Hash] a hash containing :exit_code, :stdout and :stderr
    def run(opts)
      dest = opts[:n].name
      cmd = opts[:c]

      ssh_channels = RSpec.configuration.ssh_channels
      puts "-----------------"
      puts "#{dest}$ #{cmd}"
      result = ssh_exec!(ssh_channels[dest], "cd /tmp && sudo sh -c '#{cmd}'")
      puts "-----------------"
      result
    end

    # Transfer files to a host in the NodeSet.
    #
    # @param opts [Hash] options
    # @return [Boolean] returns true if command succeeded, false otherwise
    # @todo This is damn ugly, because we ssh in as vagrant, we copy to a temp
    #   path then move it later. Its slow and brittle and we need a better
    #   solution. Its also very Linux-centrix in its use of temp dirs.
    def rcp(opts)
      #log.debug("[Vagrant@rcp] called with #{opts.inspect}")

      dest = opts[:d].name
      source = opts[:sp]
      dest_path = opts[:dp]

      # Grab a remote path for temp transfer
      tmpdest = tmppath

      # Do the copy and print out results for debugging
      cmd = "scp -r -F '#{ssh_config}' '#{source}' #{dest}:#{tmpdest}"
      puts "------------------"
      puts "localhost$ #{cmd}"
      r = systemu cmd

      result = {
        :exit_code => r[0].exitstatus,
        :stdout => r[1],
        :stderr => r[2]
      }

      print "#{result[:stdout]}"
      print "#{result[:stderr]}"
      puts "Exit code: #{result[:exit_code]}"

      # Now we move the file into their final destination
      result = run(:n => opts[:d], :c => "mv #{tmpdest} #{dest_path}")
      if result[:exit_code] == 0
        return true
      else
        return false
      end
    end

    # Create the Vagrantfile for the NodeSet.
    #
    # @api private
    def create_vagrantfile
      log.info "[Vagrant#create_vagrantfile] Creating vagrant file here: #{@vagrant_path}"
      FileUtils.mkdir_p(@vagrant_path)
      File.open(File.expand_path(File.join(@vagrant_path, "Vagrantfile")), 'w') do |f|
        f.write('Vagrant::Config.run do |c|')
        nodes.each do |k,v|
          log.debug "Filling in content for #{k}"

          ps = v.provider_specifics['vagrant']

          f.write(<<-EOS)
  c.vm.define '#{k}' do |v|
    v.vm.host_name = '#{k}'
    v.vm.box = '#{ps['box']}'
    v.vm.box_url = '#{ps['box_url']}'
    v.vm.base_mac = '#{randmac}'
  end
          EOS
        end
        f.write('end')
      end
      log.debug "[Vagrant#create_vagrantfile] Finished creating vagrant file"
      nil
    end

    # Here we get vagrant to drop the ssh_config its using so we can monopolize
    # it for transfers and custom stuff. We drop it into a single file, and
    # since its indexed based on our own node names its quite ideal.
    #
    # @api private
    # @return [String] path to ssh_config file
    def ssh_config
      ssh_config_path = File.expand_path(File.join(@vagrant_path, "ssh_config"))
      begin
        File.unlink(ssh_config_path)
      rescue Errno::ENOENT
      end
      self.nodes.each do |k,v|
        Dir.chdir(@vagrant_path) do
          result = systemu("vagrant ssh-config #{k} >> #{ssh_config_path}")
          puts result.inspect
        end
      end
      ssh_config_path
    end

    # Execute vagrant command in vagrant_path
    #
    # @api private
    # @param args [String] args to vagrant
    # @todo This seems a little too specific these days, might want to
    #   generalize. It doesn't use systemu, because we want to see the output
    #   immediately, but still - maybe we can make systemu do that.
    def vagrant(args)
      Dir.chdir(@vagrant_path) do
        system("vagrant #{args}")
      end
      nil
    end

    # Return a random string of chars, used for temp dir creation
    #
    # @api private
    # @return [String] string of 50 random characters A-Z and a-z
    def random_string
      o =  [('a'..'z'),('A'..'Z')].map{|i| i.to_a}.flatten
      (0...50).map{ o[rand(o.length)] }.join
    end

    # Generates a random string for use in remote transfers.
    #
    # @api private
    # @return [String] a random path
    # @todo Very Linux dependant, probably need to consider OS X and Windows at
    #   least.
    def tmppath
      '/tmp/' + random_string
    end

    # Return a random mac address
    #
    # @api private
    # @return [String] a random mac address
    def randmac
      "080027" + (1..3).map{"%0.2X"%rand(256)}.join
    end

    # Execute command via SSH.
    #
    # A special version of exec! from Net::SSH that returns exit code and exit
    # signal as well. This method is blocking.
    #
    # @api private
    # @param ssh [Net::SSH::Connection::Session] an active ssh session
    # @param command [String] command to execute
    # @return [Hash] a hash of results
    def ssh_exec!(ssh, command)
      r = {
        :stdout => '',
        :stderr => '',
        :exit_code => nil,
        :exit_signal => nil,
      }
      ssh.open_channel do |channel|
        channel.exec(command) do |ch, success|
          unless success
            abort "FAILED: couldn't execute command (ssh.channel.exec)"
          end
          channel.on_data do |ch,data|
            d = data
            print d
            r[:stdout]+=d
          end

          channel.on_extended_data do |ch,type,data|
            d = data
            print d
            r[:stderr]+=d
          end

          channel.on_request("exit-status") do |ch,data|
            c = data.read_long
            puts "Exit code: #{c}"
            r[:exit_code] = c
          end

          channel.on_request("exit-signal") do |ch, data|
            s = data.read_string
            puts "Exit signal: #{s}"
            r[:exit_signal] = s
          end
        end
      end
      ssh.loop

      r
    end
  end
end
