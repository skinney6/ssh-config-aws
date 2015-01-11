#!/usr/bin/env ruby
require 'aws-sdk'
require 'optparse'

Dir.chdir File.expand_path File.dirname(__FILE__)

options = {}
optparse = OptionParser.new do |opts|
  options[:profile] = "" 
  opts.on( '-f', '--profile FILE', "Profile name. This file holds the creds to query aws." ) do |f| 
    options[:profile] = f 
  end 
  options[:proxy] = false
  opts.on('-p', '--proxy', 'Turn on proxy config generation.') do
    options[:proxy] = true
  end
  options[:jump_user] = 'ubuntu'
  opts.on('-u', '--user USER_NAME', 'The username you log into jump with. Only required if '-p' is on.') do |username|
    options[:jump_user] = username
  end
  options[:jump_key] = 'id_rsa'
  opts.on('-k', '--key KEY_NAME', 'The key you log into jump with. Only required if '-p' is on.') do |key|
    options[:jump_key] = key
  end
  opts.on( '-h', '--help', 'Display this screen' ) do 
    puts opts 
    exit 
  end 
end

optparse.parse! 

config = File.read("aws/#{options[:profile]}.profile")
    
access_key_id = config.match(/AWS_ACCESS_KEY=(.+)/)[1]
secret_access_key = config.match(/AWS_SECRET_KEY=(.+)/)[1]

# Add more regions here if necessary. No harm in adding all of them, just makes the generation take longer to query more regions.
regions = [
  'us-east-1',
  'us-west-1'
]

if options[:proxy]
  ssh_config = "Host jump.zenti.com\n  Port 19750\n  HostName jump.zenti.com\n  User #{options[:jump_user]}\n  IdentityFile ~/.ssh/#{options[:jump_key]}\n\n"
else
  ssh_config = ''
end

regions.each do |region|
  AWS.config access_key_id: access_key_id, secret_access_key: secret_access_key, region: region
  ec2 = AWS.ec2

  ec2.instances.each do |instance|

    if(instance.status == :running && instance.tags['Name'])
      instance_name = instance.tags['Name'].gsub /[^a-zA-Z0-9\-_\.]/, '-'
      instance_user = instance.tags['User'] || 'ubuntu'
      if instance_name == 'jump.zenti.com'
        next
      else
        if instance_name =~ /twit3/
          puts "#{instance.id}: #{instance_name} #{instance.public_ip_address} (#{instance_user})"
        else
          puts "#{instance.id}: #{instance_name} #{instance.private_ip_address} (#{instance_user})"
        end
        ssh_config << "Host #{instance_name}\n"
        if instance_name =~ /twit3/
          ssh_config << "  HostName #{instance.public_ip_address}\n"
        else
          ssh_config << "  HostName #{instance.private_ip_address}\n"
          ssh_config << "  ProxyCommand ssh jump.zenti.com -W %h:%p\n" if options[:proxy]
        end
        ssh_config << "  User #{instance_user}\n"
        if instance.key_name.end_with?('.pem')
          ssh_config << "  IdentityFile ~/.ssh/#{instance.key_name}\n"
        else
          ssh_config << "  IdentityFile ~/.ssh/#{instance.key_name}.pem\n"
        end
        ssh_config << "\n"
      end
    end
  end
end

ssh_file = "ssh/#{options[:profile]}.sshconfig"
File.open(ssh_file, 'w') {|f| f.write(ssh_config) }

puts "Complete! Now run rebuild-ssh-config.sh to update your .ssh/config file"
