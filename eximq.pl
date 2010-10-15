#!/usr/bin/perl -w

## eximq
##
## (c) 2003-2004 Piotr Roszatycki <dexter@debian.org>, GPL
##
## $Id$

=head1 NAME

eximq - Supervising process for Exim's queue runners.

=head1 SYNOPSIS

B<eximq> B<-h>|B<--help>

B<eximq> [B<--debug-stderr>] [B<--debug-syslog>]
[B<--daemon>] S<[B<--pidfile> I<path>]>
I<agemin> I<agemax> I<interval> I<processmax> [I<exim_q_command>]

=cut

use 5.006;
use strict;

use Getopt::Long qw(:config require_order no_auto_abbrev);
use POSIX qw(:sys_wait_h :locale_h setsid);
use Pod::Usage;
use Unix::Syslog qw(:macros :subs);


##############################################################################

## Constant variables
##

## Program name
my $NAME = "eximq";

## Program version
my $VERSION = 0.4;

## Global variables
##

## Spawned command
my @eximq_cmd = qw(/usr/sbin/exim -q);


##############################################################################

## Private variables
##

## Count for running spawned processes
my $running = 0;

## Process group ID
my $pgrp = 0;

## Getopt::Long handler
my %opt = (
    'pidfile' => "/var/run/$NAME.pid",
);

## Old value for LC_TIME
my $old_lc_time = setlocale(LC_TIME);


##############################################################################

## debug($msg)
##
## Dumps message if debug mode is turned on.
##
sub debug(@) {
    my (@msg) = @_;

    if (${opt{'debug-syslog'}}) {
        setlocale(LC_TIME, "C");
        openlog($NAME, LOG_PID, LOG_MAIL);
        syslog(LOG_INFO, "%s", join('', @msg));
        closelog;
        setlocale(LC_TIME, $old_lc_time);
    }
    if (${opt{'debug-stderr'}}) {
        print STDERR "*** @msg\n";
    }
}


## error($msg)
##
## Dumps error message
##
sub error(@) {
    my (@msg) = @_;

    setlocale(LC_TIME, "C");
    openlog($NAME, LOG_PID, LOG_MAIL);
    syslog(LOG_ERR, "%s", join('', @_));
    closelog;
    setlocale(LC_TIME, $old_lc_time);
    print STDERR "*** @_\n";
}


## sig_handler($)
##
## Handler for process signal
##
sub sig_handler($) {
    my($sig) = @_;
    cleanup();
    return unless defined $sig;
    debug("Got a SIG$sig");
    if ($pgrp) {
        debug("Killing spawned processes for session $pgrp");
        $SIG{'TERM'} = 'IGNORE';
        kill 'TERM', -$pgrp;
    }
    die "Die for SIG$sig\n";
}


## daemonize()
##
## Daemonize main process
##
sub daemonize() {
    chdir '/'               or die "Can't chdir to /: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>/dev/null'
                            or die "Can't write to /dev/null: $!";
    defined(my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        open PIDFILE, ">$opt{pidfile}" or die "Can't open pidfile $opt{pidfile}: $!";
        print PIDFILE "$pid\n"         or die "Can't write pidfile $opt{pidfile}: $!";
        close PIDFILE;
        exit;
    }
    $pgrp = setsid or die "Can't start a new session: $!";
    open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
}


## cleanup()
##
## Clean up before die
##
sub cleanup() {
    unlink $opt{'pidfile'} if $opt{'daemon'} and -f $opt{'pidfile'};
}


## usleep($sec);
##
## Sleep $usec seconds (can be factorized)
sub usleep($) {
    my ($sec) = @_;

    select(undef, undef, undef, $sec);
}


## $n62 = base62($n10);
##
## Convert decimal number to b62 string (part of Exim msgid)
##
sub base62($) {
    my ($n10) = @_;

    my $BASE = 62;
    my @CHAR = qw(0 1 2 3 4 5 6 7 8 9
                  A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
                  a b c d e f g h i j k l m n o p q r s t u v w x y z);

    my $n62 = "";

    while ($n10 > 0) {
        my $d = $n10 % $BASE;
        $n62 = $CHAR[$d] . $n62;
        $n10 = int $n10 / $BASE;
    }

    return $n62;
}


## $seconds = seconds($time);
##
## Converts time with modifiers [smhd] to seconds
##
sub seconds($) {
    my ($time) = @_;

    return $time if $time eq "inf";

    my $seconds = 0;

    my $modifier = "[smhd]";
    while ($time =~ s/^([\d.]+)($modifier)//) {
        if ($2 eq "s") { $seconds += $1;                $modifier = ""; }
        if ($2 eq "m") { $seconds += $1 * 60;           $modifier = "s"; }
        if ($2 eq "h") { $seconds += $1 * 60 * 60;      $modifier = "[sm]"; }
        if ($2 eq "d") { $seconds += $1 * 60 * 60 * 24; $modifier = "[smh]"; }
    }

    return undef if $time ne "";

    return $seconds;
}


## eximq_die(@msg)
##
## Die with message
##
sub eximq_die(@) {
    my (@msg) = @_;

    $SIG{'__DIE__'} = 'DEFAULT';
    debug(@msg);
    die(@msg, "\n");
}


## eximq_exec(@cmd)
##
## Execute command
##
sub eximq_exec(@) {
    my (@cmd) = @_;

    debug("exec " . join(' ', @cmd));
    exec(@cmd);

    die "Cannot exec: $!";
}


## eximq_spawn($msgid)
##
## Spawn neq eximq process
##
sub eximq_spawn(;$$) {
    my ($msgid_min, $msgid_max) = @_;

    my $pid;
    if (!defined($pid = fork)) {
        error("Cannot fork: $!");
    } elsif ($pid) {
        debug("spawn $pid");
        $running++;
    } else {
        if (defined $msgid_max) {
            eximq_exec(@eximq_cmd, "$msgid_min-000000-00", "$msgid_max-zzzzzz-zz");
        } elsif (defined $msgid_min) {
            eximq_exec(@eximq_cmd, "$msgid_min-000000-00");
        } else {
            eximq_exec(@eximq_cmd);
        }
    }
}


## eximq_reaper()
##
## Harvest spawned eximq processes
##
sub eximq_reaper() {

    while ((my $pid = waitpid(-1,WNOHANG)) > 0) {
        debug("reap $pid");
        $running--;
    }
    $SIG{CHLD} = \&eximq_reaper;
}


## eximq($agemin, $agemax, $interval, $processmax);
##
## Start Exim queue processing
##
sub eximq($$$$) {
    my ($agemin, $agemax, $interval, $processmax) = @_;
    my $time_last = time;

    $SIG{'__DIE__'} = \&eximq_die;
    $SIG{$_} = 'IGNORE' foreach (qw(HUP PIPE USR1 USR2));
    $SIG{$_} = \&sig_handler foreach (qw(INT QUIT TERM));
    $SIG{'CHLD'} = \&eximq_reaper;

    for (;;) {
        if ($time_last + $interval < time && $running < $processmax) {
            $time_last = time;
            if ($agemax > 0 || $agemax eq "inf") {
                my $msgid_min = "000000";
                if ($agemax > 0) {
                    $msgid_min .= base62($time_last - $agemax);
                    $msgid_min =~ s/^.*(.{6})$/$1/;
                }
                if ($agemin > 0 || $agemin eq "inf") {
                    my $msgid_max = "000000";
                    if ($agemin > 0) {
                        $msgid_max .= base62($time_last - $agemin);
                        $msgid_max =~ s/^.*(.{6})$/$1/;
                    }
                    eximq_spawn($msgid_min, $msgid_max);
                } else {
                    eximq_spawn($msgid_min);
                }
            } else {
                eximq_spawn();
            }
        }
        sleep(1);
    }
}


## main()
##
## Main subroutine
##
sub main() {

    ## get options
    my $opt = GetOptions(\%opt,
        'help|h|?',
        'debug-stderr',
        'debug-syslog',
        'daemon|d',
        'pidfile|p=s',
    );

    pod2usage(2) unless $opt;

    pod2usage(-verbose=>1, -message=>"$NAME $VERSION\n") if $opt{'help'};

    pod2usage(2) if $#ARGV < 3;

    ## set the process name
    $0 = join(' ', $0, @ARGV);

    my ($agemin, $agemax, $interval, $processmax);
    defined ($agemin = seconds(shift @ARGV)) or die "Bad format for agemin argument\n";
    defined ($agemax = seconds(shift @ARGV)) or die "Bad format for agemax argument\n";
    ($agemin <= $agemax || $agemax eq "inf") or die "agemin argument cannot be greater than agemax argument\n";
    defined ($interval = seconds(shift @ARGV)) or die "Bad format for interval argument\n";
    ($processmax = shift @ARGV) =~ /^\d+$/ or die "Bad format for max argument\n";

    if (@ARGV) {
        @eximq_cmd = @ARGV;
    }

    daemonize() if $opt{'daemon'};
    eximq($agemin, $agemax, $interval, $processmax);
}


END: {
    cleanup();
}


main();


__END__

=head1 DESCRIPTION

The B<eximq> controlls the count of queue runner processes based on
messages age.  This allows to keep low system load and maximum number of
queue runner processes.

The B<eximq> can be started as daemon or foregound process.  The example
init script is available as separate file and it requires F<eximq.args>
file which contains arguments for each B<eximq> instances.

The example F<eximq.args> file:

 0s 1m 5s 10
 1m 2m 15s 10
 2m 5m 30s 10
 5m 15m 1m 5 /usr/sbin/exim -qq
 15m 2h 2m 5 /usr/sbin/exim -qq
 2h inf 5m 5 /usr/sbin/exim -qq

Also, the B<eximq> can be started from F</etc/inittab> file. I.e.:

 # Exim queue
 ex01:23:respawn:+/usr/sbin/eximq 0s 1m 5s 10
 ex02:23:respawn:+/usr/sbin/eximq 1m 2m 15s 10
 ex03:23:respawn:+/usr/sbin/eximq 2m 5m 30s 10
 ex04:23:respawn:+/usr/sbin/eximq 5m 15m 1m 5 /usr/sbin/exim -qq
 ex05:23:respawn:+/usr/sbin/eximq 15m 2h 2m 5 /usr/sbin/exim -qq
 ex06:23:respawn:+/usr/sbin/eximq 2h inf 5m 5 /usr/sbin/exim -qq

In this example the B<eximq> is started three times with different message
ages.  The first process spawn max 10 queue runners each 5th second for
messages not older than 1 minute.  The second process spawn max 10 runners
each minute for messages not older than 5 minutes and nor newer than 1 minute.
The last queue runners work for messages older than 2 hours and are spawned
each 5th minute.

The queue runner is spawned as B</usr/sbin/exim -q> command as default.
Different command can be specified as last argument.

For best result you should put

 queue_only = yes
 queue_smtp_domains = *

in your F</etc/exim/exim.conf> configuration file.

=head1 OPTIONS

=over 8

=item I<minage>

Minimal age of message.  The queue runner will be process messages not newer
than I<minage>.  B<0s> means no limits.

=item I<maxage>

Maximal age of message.  The queue runner will be process messages not older
than I<maxage>.  B<inf> means no limits.  I<maxage> can not be lower than
I<minage>.

=item I<interval>

Interval time between spawning another queue runner.  The new runner will be
not spawned if the I<interval> time was not reached.

=item I<processmax>

Maximal number of spawned processes.  The new runner will be not spawned if
whole number of running processes will be greater than I<processmax>.

=item I<exim_q_command>

The queue runner command.  The default is B</usr/sbin/exim -q>.

=item B<--debug-stderr>

Turn on debug mode on stderr.

=item B<--debug-syslog>

Turn on debug mode on syslog (MAIL|INFO).

=item B<--daemon>

Runs the B<eximq> as daemon. In this mode it creates pidfile and
detaches from terminal.

=item B<--pidfile> I<path>

The I<path> for pidfile which is created if B<eximq> is started in
daemon mode.  The default I<path> is F</var/run/eximq.pid>.  The file is
removed after daemon dies.

=item B<-h>|B<--help>

This help.

=back

=head1 SIGNALS

The B<eximq> ignores B<HUP>, B<PIPE>, B<USR1> and B<USR2> and dies for B<INT>,
B<QUIT> and B<TERM>. It kills all spawned processes with B<TERM> after die
signal.

=head1 SEE ALSO

B<exim>(8)

=head1 AUTHOR

(c) 2003-2004 Piotr Roszatycki E<lt>dexter@debian.orgE<gt>

All rights reserved.  This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License, the
latest version.
