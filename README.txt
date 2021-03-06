NOTE: IF YOU ARE RUNNING VERSION 0.2.6 FROM 8 Jan 2010, PLEASE UPDATE!
There is a bug that can lead to files not being backed up! Obviously,
not desirable behavior in a backup program.

-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
README.txt  -  backups.rb
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

Backups.rb is a easily-configured wrapper for doing server-based backups
using rdiff-backup and duplicity.

It combines a lot of the functionality of these programs into an easily
scheduled backup system that will do some end-to-end verifications, send
email reports, more!

---------------------------------------------------------------------------
Basic Concepts
---------------------------------------------------------------------------
All backups are from a directory on a "source" host to a directory on a
"destination" host.

We have two tools for backing up: rdiff-backup, and duplicity.

rdiff-backup can backup from any local or remote source to any local or
remote destination. Both sources and destinations must have rdiff-backup
installed, and support ssh logins. Rdiff-backup allows you to keep
revisions -- you cannot only restore a deleted file, but you could restore
an earlier version of it, should you so choose.

duplicity can backup from the local machine to any local or remote
destination. It does not require anything to be installed on the
destination other than a daemon that will accept connections, e.g., ftp or
scp. Duplicity keeps revisions like rdiff-backup, and can also encrypt
the data, so you can store your backups safely on an untrustworthy
server.

Example:

host1 is a linux server.
host2 is a linux server.
host3 is some unknown server where we have an ftp account.

We want to backup host1 and host2 on host3.

We could either:
- run backups.rb on both host1 and host2, and use duplicity to back them
  up to host3.
- run backups.rb on host1, use rdiff-backup to keep a copy of host2 on
  host1, and use duplicity to back up to host3.

---------------------------------------------------------------------------
Requirements
---------------------------------------------------------------------------
rdiff-backup requires:
- Python v2.2 or later
- librsync v0.9.7 or later

duplicity requires:
- Python v2.2 or later
- librsync v0.9.6 or later
- GnuPG if you'll be doing encryption

backups.rb requires:
- Ruby (anything recent, recommend 1.8.5 or later)
- rdiff-backup and/or duplicity

---------------------------------------------------------------------------
Installing
---------------------------------------------------------------------------
- download/install rdiff-backup.
  http://www.nongnu.org/rdiff-backup/index.html

- download/install duplicity.
  http://www.nongnu.org/duplicity/index.html

- make sure you can run Ruby.

- put backups.rb in some easy to remember place like /root/backups or /backups

- put backup-config.yaml and backup-tasks.yaml in that same directory

- edit the yaml files to your satisfaction (see below)

- put a copy of backup-agent.rb on any remote machines where you'll be
  doing ssh passphrase-less logins.

- implement the security configuration described below

- add backups.rb to your crontab

---------------------------------------------------------------------------
Security
---------------------------------------------------------------------------
First, read http://arctic.org/~dean/rdiff-backup/unattended.html

Do everything he says :)

Then, instead of setting your command="rdiff-backup ..." in your
authorized_keys or authorized_keys2 file on the remove server, map
the command to "backup-agent.rb".

Then you'll also need to place a copy of backup-agent.rb on each remote
server being accessed in this way. Either give an explicit path in your
authorized_keys file, or put backup-agent.rb on your path.

Feel free to edit backup-agent.rb. You can turn on/off email notification
of invalid commands. You can change which commands are permissible. You
can filter out specific characters from any command string sent in.

This all is basically to help you in case one machine gets broken into --
with normal passphrase-less logins, they'd have access to your entire
collection of machines. With this mechanism in place, they'll still have
to work hard to get access to your other machines (if they can get in
at all).

You might also want to chmod 700 your backup directory, so that only the
backup account (and root) can see the backups. If your backup-tasks.yaml
or backup-config.yaml contain any passphrases or passwords, you'll want
to prevent any wayward eyes from looking at them.

---------------------------------------------------------------------------
But How Do I Configure It?
---------------------------------------------------------------------------
There are two configuration files: backup-config.yaml,
and backup-tasks.yaml.

backup-config.yaml holds general configuration options.

backup-tasks.yaml contains your specific backup tasks.

Simple, eh what old chap? Yaml is supposed to be human-readable in
ways that XML only dreams of.

Included in this archive should be a couple of documented example files.

Read them. Study them. Learn to loathe them. If they don't tell you what
you need to know, go to The Source, and read backups.rb. After all, the
code is the canonical documentation of the configuration files.

---------------------------------------------------------------------------
Database Backup Strategies
---------------------------------------------------------------------------
Databases are notorious for not being safe to backup simply as filesystem
files. So using backup.rb, you should use a program like mysqldump or the
equivalent to dump your database safely to a file. This also magically
gives you multiple revisions of your database backup. So how do you do it?

In your backup-tasks.rb, you can have commands executed on either the
source or destination before or after the backup. So, in you source clause,
put in a line like:

pre-src: "'mysqldump -u user -p password databasename > /backupdirectory/backup.sql'"

---------------------------------------------------------------------------
Crontab Backup Strategies
---------------------------------------------------------------------------
How many times have you restored a server, only to find that your complex set
of cron-based tasks are not running. And what were those parameters you were
passing to them? drat!

The backup-agent.rb has a crontab backup command. Put it in your pre-src:

pre-src: "'crontabs root bob the_dude'"

This will dump root, bob, and the_dude's crontabs to /tmp/crontabs as
individual files. Then you can simply back 'em up as normal.

---------------------------------------------------------------------------
Round-Trip Testing
---------------------------------------------------------------------------
This requires that you're using the "backup-agent.rb" setup described in
the Security section above.

Basically, before the backups are done, a file named "backup-metadata.txt"
is placed in the top-level directory that you're backing up. In it is placed
text containing a random string.

After the backup, this file is restored to the local machine, the restored
file is searched for the random string. If it's found and it matches, it's
a pretty good indication that your backup was successful and that you can
successfully restore it.

A few things that the round-trip testing does NOT verify:
- that your pre-src, pre-dest, post-src, or post-dest scripts succeeded
- that your entire backup dataset is valid

backups.rb tries to handle error conditions coming back from all commands
it issues (say, for example, rdiff-backup crashes half-way through a
session), but there are cases where it can fail. So take that into
consideration when staking your corporate future on this script, and
keep in mind that I'm disclaiming all liability.

---------------------------------------------------------------------------
Rsync verification
---------------------------------------------------------------------------
If you don't trust rdiff-backup to get all your files, you can use the new
verify-with-rsync option, which will compare the source and destination
using rsync after backing up. If rsync thinks there are files that need to
be transferred (e.g., they vary in size or filename), backups will return
an error.

This can be problematic on rapidly-changing directories, of course, because
it's not atomic to the rdiff-backup operation. Use with discretion.

---------------------------------------------------------------------------
The Watchdog
---------------------------------------------------------------------------
backups.rb tries its best to send you email letting you know whether or not
it was successful. But there are a class of errors that will prevent that
email from occuring -- backup machine off the network, or catastrophic
things like disk failure, etc.

It's hard to remember to notice that you *didn't* receive a "Backups
Completed" or "Backups Reported an Error" email. Hence, the Watchdog.

In your backup-config.yaml, set write-completion-status to true, and
status-dir to wherever you want.

Set up watchdog-agent.rb on some remote machine, making sure it can do
password-less SSH logins like you did for the backups themselves. Edit
the config in watchdog-agent.rb to reflect the correct status-dir,
then add watchdog-agent to your crontab.

---------------------------------------------------------------------------
Troubleshooting
---------------------------------------------------------------------------

If you're, say, running Linux, but NFS mounting your home directory from
and OpenBSD machine, the GPG encryption will fail. Here's why:
http://www.ussg.iu.edu/hypermail/linux/kernel/0610.2/0582.html

As a work-around, you can use the --no-encryption flag for
duplicity-backup-flags, duplicity-restore-flags, duplicity-verify-flags,
and duplicity-purge-flags in your backup-config.yaml. Yes, that means
you get no encryption. Running as root, or some account that doesn't
NFS mount its home directory will work as well.

If you're using Duplicity to ftp somewhere, and it crashes out with
an error message like:
"Temporary error '450 No files found'. Trying to reconnect in 10 seconds."
it's evidently a Python bug triggered by an empty directory on the
destination. You can work around it by putting an empty file in your target
directory.
---------------------------------------------------------------------------
This file last updated: 28 Oct 2014
