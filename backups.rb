#!/usr/bin/ruby
#
# rdiff-backup and duplicity wrapper script
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
version = "0.2.7"
version_date = "28 Oct 2014"
#

require 'yaml'
require 'optparse'
require 'net/smtp'
require 'pp'
require 'socket'

def target_string_base(desc)
	cmd = ""
	if ! is_local(desc)
		cmd += "#{desc['username']}@" unless desc['username'].nil? || desc['username'].empty?
		cmd += desc['host'] || 'localhost'
	end
	cmd
end

def msg(text)
	$theReport += text.to_s + "\n"
	puts text
end

def local_command(cmd, config)
	if config['testing'] || config['echo-commands']
 		msg "CMD: #{cmd}"
 	end
	if ! config['testing']
	   begin
 			res =`#{cmd} 2>&1`
			if $? != 0
				msg "ERROR! Command reported error condition. Full command response: "+res
				$success = false
			else
 				msg "RES: "+res if config['verbose']
 			end
 		rescue
 		   msg "ERROR! "+$!
 		   $success = false
 		end
	end
	return res
end

def local_or_remote_cmd(command,command_name,target,config)
 	if (command && ! command.empty?)
 		msg "Running "+command_name if config['verbose']
 		cmd = ""
		cmd += "#{config['ssh-command']} " if ! is_local(target)
		cmd += target_string_base(target) + " " + command
		local_command(cmd, config)
 	end
end

def is_local(target)
  ! target['host'] || target['host'].empty? || target['host'] == "local"
end

def test_restore_rdiff_backup(thisBackup, config)
    if (File.exist?("/tmp/backup-metadata.txt"))
	    cmd = "rm /tmp/backup-metadata.txt"
	    local_command(cmd, config)
	end
	cmd = "#{config['rdiff-command']} #{thisBackup['rdiff-restore-flags']} --restore-as-of now "
	cmd += target_string_base(thisBackup['destination'])+"::" if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}/backup-metadata.txt /tmp/backup-metadata.txt"
	msg "Restoring up backup-metadata.txt from #{thisBackup['source']['host']} to /tmp/backup-metadata.txt for checking" if config['verbose']
	local_command(cmd, config)
	test_restored_file(thisBackup, config)
end

def backup_rdiff_backup(thisBackup, config)
 	cmd = "#{config['rdiff-command']} #{thisBackup['rdiff-backup-flags']} --exclude-device-files "
 	thisBackup['source']['exclude'].split(%r{[,\s]+}).each {|thisExcl| cmd += "--exclude #{thisExcl} "} if thisBackup['source']['exclude'] && !thisBackup['source']['exclude'].empty?
	cmd += target_string_base(thisBackup['source'])+"::" if ! is_local(thisBackup['source'])
 	cmd += "#{thisBackup['source']['directory']} "
	cmd += target_string_base(thisBackup['destination'])+"::" if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}"
	msg "Backing up #{thisBackup['source']['directory']} on #{thisBackup['source']['host']}" if config['verbose']
	local_command(cmd, config)
end

def verify_signatures_rdiff_backup(thisBackup, config)
 	cmd = "#{config['rdiff-command']} #{thisBackup['rdiff-verify-flags']} --exclude-device-files --verify "
 	thisBackup['source']['exclude'].split(%r{[,\s]+}).each {|thisExcl| cmd += "--exclude #{thisExcl} "} if thisBackup['source']['exclude'] && !thisBackup['source']['exclude'].empty?
	cmd += target_string_base(thisBackup['destination'])+"::" if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}"
	msg "Verifying #{thisBackup['destination']['directory']} on #{thisBackup['source']['host']}" if config['verbose']
	local_command(cmd, config)
end

def verify_using_rsync(thisBackup, config)
 	cmd = "#{config['rsync-command']} #{thisBackup['rsync-flags']} -a -i --dry-run "
 	thisBackup['source']['exclude'].split(%r{[,\s]+}).each {|thisExcl| cmd += "--exclude #{thisExcl} "} if thisBackup['source']['exclude'] && !thisBackup['source']['exclude'].empty?
	cmd += target_string_base(thisBackup['source'])+":" if ! is_local(thisBackup['source'])
 	cmd += "#{thisBackup['source']['directory']}/ "
	cmd += target_string_base(thisBackup['destination'])+"::" if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}/"

	msg "Verifying all files from #{thisBackup['source']['directory']} on #{thisBackup['source']['host']} using rsync" if config['verbose']
	res = local_command(cmd, config)
	if (res =~ /^\>/m)
	    msg "WARNING! Rsync found files needing transfer: "+res
	end
end

def cleanup_rdiff_backup(thisBackup, config)
 	cmd = "#{config['rdiff-command']} #{thisBackup['rdiff-cleanup-flags']} --remove-older-than #{thisBackup['preserve']} --force "
	cmd += target_string_base(thisBackup['destination'])+"::" if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}"
	msg "Purging increments older that #{thisBackup['preserve']}" if config['verbose']
	local_command(cmd, config)
end


def duplicity_dest_spec(thisBackup)
	if is_local(thisBackup['destination'])
		cmd = "file://"
	else
		thisBackup['destination']['protocol'] = thisBackup['destination']['protocol'] || "scp"
		case thisBackup['destination']['protocol']
			when "scp"
				cmd = "scp://"
			when "ftp"
				cmd = "ftp://"
				ENV['FTP_PASSWORD']= thisBackup['destination']['password']
		end
	end
	cmd
end

def backup_duplicity(thisBackup, config)
 	cmd = "#{config['duplicity-command']} #{thisBackup['duplicity-backup-flags']} --exclude-device-files "
 	thisBackup['source']['exclude'].split(%r{[,\s]+}).each {|thisExcl| cmd += "--exclude #{thisExcl} "} if thisBackup['source']['exclude'] && !thisBackup['source']['exclude'].empty?
    cmd += "#{thisBackup['source']['directory']} "
	cmd += duplicity_dest_spec(thisBackup)
	ENV['PASSPHRASE'] = thisBackup['destination']['pgp_passphrase']
	cmd += target_string_base(thisBackup['destination']) if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}"

	msg "Backing up #{thisBackup['source']['directory']} on #{thisBackup['source']['host']}" if config['verbose']
	local_command(cmd, config)
end

def cleanup_duplicity(thisBackup, config)
 	cmd = "#{config['duplicity-command']} #{thisBackup['duplicity-cleanup-flags']} --remove-older-than  #{thisBackup['preserve']} --force "
	cmd += duplicity_dest_spec(thisBackup)
	ENV['PASSPHRASE'] = thisBackup['destination']['pgp_passphrase']
	cmd += target_string_base(thisBackup['destination']) if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}"

	msg "Purging increments older that #{thisBackup['preserve']}" if config['verbose']
	local_command(cmd, config)
end

def test_restore_duplicity(thisBackup, config)
   if (File.exist?("/tmp/backup-metadata.txt"))
	    cmd = "rm /tmp/backup-metadata.txt"
	    local_command(cmd, config)
	end
	cmd = "#{config['duplicity-command']} #{thisBackup['duplicity-restore-flags']} --file-to-restore backup-metadata.txt "
	cmd += duplicity_dest_spec(thisBackup)
	ENV['PASSPHRASE'] = thisBackup['destination']['pgp_passphrase']
	cmd += target_string_base(thisBackup['destination']) if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']} /tmp/backup-metadata.txt"
	msg "Restoring up backup-metadata.txt from #{thisBackup['source']['host']} to /tmp/backup-metadata.txt for checking" if config['verbose']
	local_command(cmd, config)
	test_restored_file(thisBackup, config)
end

def verify_signatures_duplicity(thisBackup, config)
 	cmd = "#{config['duplicity-command']} #{thisBackup['duplicity-verify-flags']} --verify --exclude-device-files "
 	thisBackup['source']['exclude'].split(%r{[,\s]+}).each {|thisExcl| cmd += "--exclude #{thisExcl} "} if thisBackup['source']['exclude'] && !thisBackup['source']['exclude'].empty?
   cmd += "#{thisBackup['source']['directory']} "
	cmd += duplicity_dest_spec(thisBackup)
	ENV['PASSPHRASE'] = thisBackup['destination']['pgp_passphrase']
	cmd += target_string_base(thisBackup['destination']) if ! is_local(thisBackup['destination'])
	cmd += "#{thisBackup['destination']['directory']}"

	msg "Verifying #{thisBackup['source']['directory']} on #{thisBackup['source']['host']}" if config['verbose']
	local_command(cmd, config)
end

def test_restored_file(thisBackup, config)
	if ! config['testing']
		file_cont = []
		begin
			fin = File.open("/tmp/backup-metadata.txt", "r")
    		while line = fin.gets
      		file_cont.push(line.chomp)
    		end
    	rescue
    		msg "ERROR! "+$!
    		$success = false
    	ensure
    		fin.close unless fin.nil?
    	end
    	if file_cont[0] != thisBackup['temp-file']
      	# restore failed!
      	msg "Failed! [#{file_cont[0]}] != [#{thisBackup['temp-file']}]"
      	$success = false
      else
      	# succeeded!
      	msg "Succeeded!"
		end
      cmd = "rm /tmp/backup-metadata.txt"
		local_command(cmd, config)
  end
end

def write_testfile(thisBackup, config)
	if is_local(thisBackup['source'])
		if config['testing'] || config['echo-commands']
 			msg "Write temp file #{thisBackup['source']['directory']}/backup-metadata.txt"
 		end
		if ! config['testing']
			begin
				fout = File.open("#{thisBackup['source']['directory']}/backup-metadata.txt", "w")
				fout.puts("#{thisBackup['temp-file']}")
			rescue
				msg "ERROR! "+$!
				$success = false
			ensure
				fout.close unless fout.nil?
			end
		end
	else
		if config['testing'] || config['echo-commands']
 			msg "Write temp file #{thisBackup['source']['host']}::#{thisBackup['source']['directory']}/backup-metadata.txt"
 		end
 		if ! config['testing']
			local_or_remote_cmd("timestamp #{thisBackup['source']['directory']} \"#{thisBackup['temp-file']}\"",
				"Write temp file", thisBackup['source'], config)
		end
	end
end

def write_status_tag(successful, completely, config)
		begin
         fout = File.open((config['status-dir']||"/tmp")+"/backup-stat.txt", "w")
         fout.puts Time.now.to_s + "|" + successful.to_s + ',' + completely.to_s
		rescue
			msg "ERROR! "+$!
		ensure
			fout.close unless fout.nil?
		end
end

def human_readable_time(seconds)
   ret = ''

    if (seconds >= 86400)
        tmp = Integer(seconds / 86400);
        ret = ret + tmp.to_s + 'd ';
        seconds -= (86400 * tmp);
    end
    if (seconds >= 3600)
        tmp = Integer(seconds / 3600);
        ret = ret + tmp.to_s + 'h ';
        seconds -= (3600 * tmp);
    end
    if (seconds >= 60)
        tmp = Integer(seconds / 60);
        ret = ret + tmp.to_s + 'm ';
        seconds -= (60 * tmp);
    end
    ret = ret + sprintf("%0.1f",seconds) + 's'

   return ret
end

# -----------------------------------------------------
# Main Operation
# -----------------------------------------------------
start_time = Time.new
task_file = 'backup-tasks.yaml'
config_file = 'backup-config.yaml'
verbose = false
testing = false
$theReport = ""
$success = true
allitems = true
sample_status = false
theSummary = ""

OptionParser.new do |opts|
	opts.banner = "Usage: backups.rb [options]"
	opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
		verbose = v
	end
	opts.on("-b", "--backup-tasks task-file", "Backup task yaml file (default backup-tasks.yaml)") do |b|
		task_file = b;
	end
	opts.on("-c", "--backup-config configfile", "Backup config yaml file (default backup-config.yaml)") do |c|
		config_file = c;
	end
	opts.on("-t", "--[no-]test", "Run in test mode (do not issue commands)") do |t|
		testing = t
	end
	opts.on("-s", "--status", "Write a sample status file and quit (for testing watchdog)") do |s|
		sample_status = s
	end
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
   opts.on_tail("--version", "Show version") do
      puts "backup.rb version #{version}: #{version_date}"
      exit
   end
end.parse!

begin
   config = YAML.load_file(config_file)
   backups = YAML.load_file(task_file)
  
   config['verbose'] = verbose 
   config['testing'] = testing

   if sample_status
      write_status_tag(true, true, config)
      config['email-report'] = false
      exit
   end


   msg '-='*35 + '-'
   msg Time.new
   msg 'Starting backup process on '+Socket.gethostname+'...'
   msg '-='*35 + '-'
   msg 'Running in test mode -- no actual commands will be issued' if config['testing']
   dow = Integer(Time.now.localtime.strftime("%w"))
   dom = Integer(Time.now.localtime.strftime("%d").gsub(/0(\d)/, '\1'))
   day=['s','m','t','w','T','f','S'][dow]

   backups.each do
   	|thisBackup|
   	op_time = Time.new
   	msg '-'*71
   	msg "Backup task: #{thisBackup['name']} initiating at "+Time.now.localtime.strftime("%Y-%m-%d %H:%M:%S")+"\n\n" if thisBackup['name'] && ! thisBackup['name'].empty?
      theSummary += "#{thisBackup['name']}: "
   	thisBackup['temp-file'] = "backup-rt-"+Time.now.localtime.strftime("%Y-%m-%d")+"."+(1..4).collect { (i = Kernel.rand(62); i += ((i < 10) ? 48 : ((i < 36) ? 55 : 61 ))).chr }.join+".txt"
   	thisBackup['mail-out'] = ""
   
      if thisBackup['option-set'] && ! thisBackup['option-set'].empty?
         begin
            config['option-sets'][thisBackup['option-set']].each do
         		|key,val|
               if (key == 'source' || key == 'destination')
                  val.each do
                     |skey,sval|
                     thisBackup[key][skey] = thisBackup[key][skey] || sval
                  end
               else
                  thisBackup[key] = val if thisBackup[key].nil?
               end
      		end
   		rescue
            puts "Invalid option set #{thisBackup['option-set']} specified."
            exit
   		end
   	end

   	['source','destination'].each do
   		|target|
   		if thisBackup[target]['location'] && !thisBackup[target]['location'].empty?
   			['host','directory','protocol','username','password','pgp-passphrase','exclude','week-days','days-of-month'].each do
   				|var| thisBackup[target][var] = thisBackup[target][var] ||
   					config['locations'][thisBackup[target]['location']][var] || ''
   			end
   		end
   	end
   
   	['preserve','rdiff-backup-flags','rdiff-restore-flags','rdiff-verify-flags',
   	 'rdiff-cleanup-flags','duplicity-backup-flags','duplicity-restore-flags',
   	 'duplicity-verify-flags','duplicity-cleanup-flags','rsync-flags'].each do
   	   |param|
   		thisBackup[param] = thisBackup[param] || config[param]
   	end
   
   	if ! thisBackup.has_key?('disabled') || ! thisBackup['disabled']
         weekday_match = (! thisBackup.has_key?('week-days')) ||
                           thisBackup['week-days'].include?(day)
         monthday_match = (! thisBackup.has_key?('days-of-month')) ||
                           thisBackup['days-of-month'].match(Regexp.new('\b'+dom.to_s()+'\b'))
         if ( weekday_match && monthday_match )
      	   # a few more defaults
      	     thisBackup['source']['host'] = thisBackup['source']['host'] || "local"
      	   thisBackup['destination']['host'] = thisBackup['destination']['host'] || "local"

      	   if thisBackup['destination']['host'] == 'local'
      	   	if ! FileTest.exists?(thisBackup['destination']['directory'])
      				dirList = thisBackup['destination']['directory'].split(/\//)
      				dirList.each {|seg| puts "[#{seg}]"}
      				dirPath = ""
      				dirList.each do
      					|pathelem|
      					if ! pathelem.empty?
      					dirPath += '/' + pathelem
      						if ! FileTest.exists?(dirPath)
      							Dir.mkdir(dirPath)
      						end
      					end
      				end
      	   	end
      		end

      		if thisBackup['roundtrip-test']
      			write_testfile(thisBackup, config)
      		end


            local_or_remote_cmd(thisBackup['pre-src'],"Source pre-backup script",thisBackup['source'],config)
            local_or_remote_cmd(thisBackup['pre-dest'],"Destination pre-backup script",thisBackup['destination'],config)

      	   case thisBackup['backup-engine']
      		   when "rdiff-backup"
      			   backup_rdiff_backup(thisBackup, config)
      		   when "duplicity"
      			   backup_duplicity(thisBackup, config)
      	   end

            local_or_remote_cmd(thisBackup['post-src'],"Source post-backup script",thisBackup['source'],config)
            local_or_remote_cmd(thisBackup['post-dest'],"Destination post-backup script",thisBackup['destination'],config)

      		if thisBackup['verify-signatures']
      		   case thisBackup['backup-engine']
      			   when "rdiff-backup"
      				   verify_signatures_rdiff_backup(thisBackup, config)
      			   when "duplicity"
      					verify_signatures_duplicity(thisBackup, config)
      			end
      		end

      		if thisBackup['roundtrip-test']
      		   case thisBackup['backup-engine']
      			   when "rdiff-backup"
      				   test_restore_rdiff_backup(thisBackup, config)
      			   when "duplicity"
      					test_restore_duplicity(thisBackup, config)
      		   end
      		end

      		if thisBackup['verify-with-rsync']
      		   case thisBackup['backup-engine']
      			   when "rdiff-backup"
      				   verify_using_rsync(thisBackup, config)
      			   when "duplicity"
      					msg "verify-with-rsync is unsupported for duplicity."
      		   end
      		end

      		if thisBackup['preserve']
      			# run cleanup script
      		   case thisBackup['backup-engine']
      			   when "rdiff-backup"
      				   cleanup_rdiff_backup(thisBackup, config)
      			   when "duplicity"
      					cleanup_duplicity(thisBackup, config)
      		   end
      		end
         else
            if ! weekday_match
               msg "Skipped because today is '#{day}' and this set is scheduled for '#{thisBackup['week-days']}'"
            end

            if ! monthday_match
               msg "Skipped because today is '#{dom}' and this set is scheduled for '#{thisBackup['days-of-month']}'"
            end
         end
      else
      	msg "Operations for this task disabled in backup-tasks.yaml"
         allitems = false
      end
   
    	msg "Operation completed at "+Time.now.localtime.strftime("%Y-%m-%d %H:%M:%S")+" in #{human_readable_time(Time.new - op_time)} (#{Time.new - op_time} seconds)."
    	theSummary += "#{human_readable_time(Time.new - op_time)}\n"
   end
   
   msg '-'*71
   msg "Timing Summary"
   msg '-'*71
   msg theSummary
   msg '-'*71
   msg '-='*35 + '-'
   msg "Whole enchilada completed at "+Time.now.localtime.strftime("%Y-%m-%d %H:%M:%S")+" in #{human_readable_time(Time.new - start_time)} (#{Time.new - start_time} seconds)."
   msg '-='*35 + '-'
rescue
   # caught a critical unhandled error in the backup process.
   msg "Encountered critical error: #{$!}"
   $@.each {|line| msg line}
   msg "Backup aborting"
   $success = false
ensure
   # We try to send the mail. If there is a fatal error here, it would be impossible to report anyway.
   if config['email-report']
   	theMessage = "From: #{config['report-from']}\n" +
   		"To: #{config['report-to']}\n" +
   		"Subject: "
   
   	theMessage += config['report-success-subject'] if ($success)
   	theMessage += config['report-skipped-subject'] if ($success && ! allitems)
   	theMessage += config['report-error-subject'] unless ($success)

   	theMessage += "\n\n" + $theReport
   	Net::SMTP.start(config['smtp-server']||'localhost', 25,
   		config['smtp-helo-domain']||'localhost.localdomain',
   		config['smtp-user']||nil, config['smtp-password']||nil, :login) do |smtp|
     				smtp.send_message theMessage, config['report-from'], config['report-to'].split(%r{,\s*})
     		end
   end
   
   if config['write-completion-status']
      write_status_tag($success, allitems, config)
   end
end

