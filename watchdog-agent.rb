#!/usr/bin/ruby
#
# backups.rb remote watchdog agent
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
require 'time'

#-------------------------------------------------------------------------
# set your server details here
#-------------------------------------------------------------------------
# host to check on - set this up with passwordless SSH login
check_host = 'host-to-watch'
# directory that backups.rb is writing its status tag
status_dir = '/tmp'
# how many days old the status tag may be before it's considered
# a problem. If you run backups daily, setting this to 1 is best.
time_window = 1
# email details
alert_to = 'you@yourdomain.com'
alert_from = 'backups@yourdomain.com' # this can be a comma-delimited list
email_subject = 'Backup Watchdog Reporting Error!'
smtp_server='smtp.youdomain.com'
smtp_helo_domain=nil
smtp_user=nil
smtp_password=nil
#-------------------------------------------------------------------------
version = 0.1
version_date = "4 Jan 2008"
verbose = true
report = ''
success = true
cmd = "ssh #{check_host} status #{status_dir}"

res =`#{cmd} 2>&1`
if $? != 0
	puts "ERROR! Command reported error condition. Full command response: "+res if verbose
	success = false
else
	puts "RES: "+res if verbose
end

if success && res.empty?
   success = false
end

if success && res.include?("ERROR")
   success = false
end

if success
   statBits = res.split("/")
   statDate = Time.parse(statBits[0])
   if (Time.now - statDate) > time_window * 86400
      success = false
   end
   # eventually, this might want to check the status codes
   # in statBits[1] for both being "true" as an option
   # currently, we're just checking for completion
end

if ! success
   puts "returning failure" if verbose
	theMessage = "From: #{alert_from}\n" +
			"To: #{alert_to}\n" +
			"Subject: #{email_subject}\n\n" +
			"Backups running on #{check_host} failed to update\n" +
         "status file in the last #{time_window} days. It might\n" +
         "behoove you to take a look at the backup log\n" +
			"and see what's going on.\n\n" +
			"Command issued: #{cmd}\n"+
         "Text returned: #{res}\n\n"+
			"This message generated by #{$0} running on\n" +
         "#{ENV['HOSTNAME']} at #{Time.now}\n"
	Net::SMTP.start(smtp_server||'localhost', 25,
			smtp_helo_domain||'localhost.localdomain',
			smtp_user||nil, smtp_password||nil, :login) do |smtp|
  				smtp.send_message theMessage, alert_from, alert_to.split(%r{,\s*})
  	end
end
