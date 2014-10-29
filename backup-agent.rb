#!/usr/bin/env ruby
#
# backups.rb remote agent
# SjG <samuel@1969web.com>
#
#-------------------------------------------------------------------------
# LICENSE (tl;dr -> BSD)
#-------------------------------------------------------------------------
# Copyright (c) 2011, Samuel Goldstein
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
# 
#     Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
# 
#     Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
# 
#     Neither the name of Samuel Goldstein nor the names of contributors
#     may be used to endorse or promote products derived from this software
#     without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CON-
# SEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUB-
# STITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#-------------------------------------------------------------------------
# 

require 'net/smtp'

version = 0.4
version_date = '28 Oct 2014'
verbose = false

#-------------------------------------------------------------------------
# edit these as you see fit
legal_commands = [
	'timestamp',
	'status',
	'date',
	'rdiff-backup',
	'rsync',
	'duplicity',
	'mysqldump',
	'pg_dump',
	'pg_dumpall',
	'vm_suspend',
	'vm_resume',
	'crontabs',
	'info'
	]

# illegal commands - these strings will get removed even
# if they're parameters to another command
illegal_commands = ['rm','su']

# illegal substrings - these substrings will get removed
# from commands or parameters
illegal_substrings = [';']

# legal directories to permit for status checks
legal_directories = ['/backups']

# VMWare Server Controls
# if you're backing up VMWare Virtual Machines
# there are some commands to support suspending before backup
# and resuming afterwards:
vmware_user = ''
vmware_password = ''
vmware_datastore = 'standard'

#-------------------------------------------------------------------------
# want to receive email when hackers are banging at the door? Change the
# next line to "true" and set your server details
email_errors = false
alert_to = 'you@yourdomain.com'
alert_from = 'backups@yourdomain.com' # this can be a comma-delimited list
email_subject = 'Backup Agent Error!'
smtp_server='smtp.yourdomain.com'
smtp_helo_domain='yourdomain.com'
smtp_user=nil
smtp_password=nil
#-------------------------------------------------------------------------

orig_command = ENV['SSH_ORIGINAL_COMMAND']
illegal_substrings.each { |pattern| orig_command =
	orig_command.gsub(/#{pattern}/, "") }

#orig_command.gsub!(/\'([^\s]+)\s([^\s]+)\'/,'\1%\2')
if orig_command.index("'")
	scommand = orig_command.split("'")
	count = 0
	scommand.each do
		|val|
		if count%2 != 0
			val.gsub!(/\s/,'%')
		end
		count += 1
	end
	orig_command = scommand.join(" ")
end
command_list = orig_command.split(' ')

command_list.each do
	|cmd|
	cmd.gsub!(/\%/," ")
	end

if legal_commands.find{|legal| command_list[0]==legal} != nil
	puts "ok: #{command_list[0]}" if verbose
	clean = command_list.map do
		 |param|
		 param unless illegal_commands.find{|illegal| param==illegal} != nil
	end

	if clean[0] == 'timestamp'
		begin
			fout = File.open("#{clean[1]}/backup-metadata.txt", "w")
			fout.puts("#{clean[2]}")
		rescue
			puts "ERROR! "+$!
		ensure
			fout.close unless fout.nil?
		end
	elsif clean[0] == 'vm_suspend'
		begin
			cmd= "/usr/bin/vmrun -h https://localhost:8333/sdk -u #{vmware_user} -p #{vmware_password} -T server suspend \"[#{vmware_datastore}] #{clean[1]}/#{clean[1]}.vmx\""
			exec cmd
		rescue
			puts "ERROR! "+$!
		end
	elsif clean[0] == 'vm_resume'
		begin
			cmd= "/usr/bin/vmrun -h https://localhost:8333/sdk -u #{vmware_user} -p #{vmware_password} -T server start \"[#{vmware_datastore}] #{clean[1]}/#{clean[1]}.vmx\""
			exec cmd
		rescue
			puts "ERROR! "+$!
		end
	elsif clean[0] == 'status'
	   if legal_directories.find{|allowed_dir| allowed_dir==command_list[1]} != nil
	     begin
		    fin = File.open("#{command_list[1]}/backup-stat.txt", "r")
			 cont = fin.gets unless fin.nil?
			 puts cont
	     rescue
	       puts "ERROR! "+$!
	     ensure
	       fin.close unless fin.nil?
	     end
	   end
	elsif clean[0] == 'info'
	   begin
	       cmd="whoami"
	       exec cmd
	   rescue
	       puts "ERROR! "+$!
	   end
    elsif clean[0] == 'crontabs'
        if ! FileTest.exists?('/tmp/crontabs')
           Dir.mkdir('/tmp/crontabs')
        end
       clean.each do
            |user|
            begin
                suser = user.gsub(/[^\d\-a-zA-Z]/, "")
                cmd = "crontab -lu #{suser} > /tmp/crontabs/#{suser}"
                 if (suser !~ /crontabs/)
                    res =`#{cmd}`
                    STDERR.puts "FAIL" if ($? != 0)
                 end
            rescue
                STDERR.puts "ERROR! "+$!
            end
         end

   else
		runstring = clean.join(" ")
		puts runstring if verbose
		exec runstring
	end
else
	if email_errors
		theMessage = "From: #{alert_from}\n" +
			"To: #{alert_to}\n" +
			"Subject: #{email_subject}\n\n" +
			"Illegal command received by #{$0}:\n"
		ENV.each{|key,val| theMessage+= "#{key} = #{val}\n"}
		Net::SMTP.start(smtp_server||'localhost', 25,
			smtp_helo_domain||'localhost.localdomain',
			smtp_user||nil, smtp_password||nil, :login) do |smtp|
  				smtp.send_message theMessage, alert_from, alert_to.split(%r{,\s*})
  		end
  	end

end
