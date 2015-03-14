#!/usr/bin/perl

##################################################################################################################
# 
# File         : webmage.pl
# Description  : keeps connections to browsers open and send them content from a updating file in real-time
# Original Date: ~1997
# Author       : simran@dn.gs
#
##################################################################################################################


require 5.002;
use Socket;
use Carp;
use FileHandle;
use POSIX;

$|=1;
$version="1.0 24/Feb/1998";

################ read in args etc... ###################################################################################
#
#
#

($cmd = $0) =~ s:(.*/)::g;
($startdir = $0) =~ s/$cmd$//g;
$printstats = 0;

while (@ARGV) { 
  $arg = "$ARGV[0]";
  $nextarg = "$ARGV[1]";
  if ($arg =~ /^-ps$/i) {
    $printstats = 1;
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-p$/i) {
    $port = $nextarg;
    die "A valid numeric port number must be given with the -p argument : $!" if ($port !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-f$/i) {
    $tracefile = $nextarg;
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-about$/i) {
    shift(@ARGV);
    &about();
  }
  else { 
    print "\n\nArgument $arg not understood.\n";
    &usage();
  }
}

#
#
#
########################################################################################################################


############### forward declarations for subroutines ... ###############################################################
#
#
#

# forward declarations for subroutines
sub strip;    # strips leading and traling whitespaces and tabs.. 
sub spawn;    # subroutine that spawns code... 
sub logmsg;   # subroutine that logs stuff on STDOUT 
sub REAPER;   # reaps zombie process... 

#
#
#
########################################################################################################################

################# main program #########################################################################################
#
#
#

$SIG{CHLD} = \&REAPER;

&usage() if (! ($port && $tracefile));

die "Please specify a port to run on with the -p argument" if (! $port);
die "Trace file not defined or not readable - please specify with -f switch : $!" if (! -r "$tracefile");

&setupServer();

&startServer();

#
#
#
########################################################################################################################


########################################################################################################################
# $str strip($string): return $string stripped of leading and trailing white spaces... 
#
#
sub strip {
  $_ = "@_";
  $_ =~ s/(^[\s\t]*)|([\s\t]*$)//g;
  return "$_";
}
#
#
#
########################################################################################################################


########################################################################################################################
# logmsg($string): prints messages to stdout
#
#
sub logmsg { 
  print "$) $$: @_ at ", scalar localtime, "\n"; 
}
#
#
#
########################################################################################################################


########################################################################################################################
# REAPER: reaps zombie processes
#
#
sub REAPER {
  my $child;
  $SIG{CHLD} = \&REAPER;
  while ($child = waitpid(-1,WNOHANG) > 0) {
    $Kid_Status{$child} = $?;
  }
  # logmsg "reaped $waitpid" . ($? ? " with exit $?" : "");
}
#
#
#
########################################################################################################################


########################################################################################################################
# setupServer: sets up server on local machine to which browsers connect 
#
#  global vars read:
#        # $port : port on which to run server 
#
#  global vars possibly created/modified:
#        # Handle: Server
#
sub setupServer { 
  my $rest;
  die "port to run server not defined in config file..." if (! $port);
  $proto = getprotobyname('tcp');
  $waitpid = 0;
  socket(Server,PF_INET,SOCK_STREAM,$proto) or die "socket: $!";
  setsockopt(Server,SOL_SOCKET,SO_REUSEADDR,pack("l",1)) or die "setsockopt: $!";
  bind(Server,sockaddr_in($port,INADDR_ANY)) or die "bind: could not bind to $port: $!";
  listen(Server,SOMAXCONN) or die "listen: $!";
  logmsg "server started on port $port";

}
#
#
#
########################################################################################################################


########################################################################################################################
# startServer: listens for connections on Server
#
#  global vars read:
#
#  global vars possibly created/modified:
#        # $client_name : hostname from which client connects
#	 # $client_port : port from which client connects
#
sub startServer { 
  for ( $waitedpid = 0; ($paddr = accept(Client,Server)) || $waitedpid; $waitedpid = 0, close Client) {
    next if $waitedpid;
    my $iaddr;
    ($client_port,$iaddr) = sockaddr_in($paddr);
    $client_name = gethostbyaddr($iaddr,AF_INET);
    # logmsg "connection from $client_name [", inet_ntoa($iaddr), "] at port $client_port";
    $client_connectime = scalar localtime;
    $fileno++;
    if ($printstats) {
      $handlenum++;
      print STDERR "\rRequests Handled : $handlenum    ";
    }
    spawn sub { 
      &handleRequest(); 
      return 1;  
    };
  }
}
#
#
#
########################################################################################################################


########################################################################################################################
# spawn: forks code
#        usage: spawn sub { code_you_want_to_spawn };
#
#
sub spawn {
  my $coderef = shift;
  unless (@_ == 0 && $coderef && ref($coderef) eq 'CODE') {
    confess "usage: spawn CODEREF";
  }
  my $pid;
  if (!defined($pid = fork)) {
    logmsg "cannot fork: $!"; return;
  }
  elsif ($pid) {
    # logmsg "begat $pid"; 
    return; # i'm the parent
  }
  # else i'm the child -- go spawn

  open(STDIN,  "<&Client")   || die "can't dup client to stdin";
  open(STDOUT, ">&Client")   || die "can't dup client to stdout";
  ## open(STDERR, ">&STDOUT") || die "can't dup stdout to stderr";
  exit &$coderef();
}
#
#
#
########################################################################################################################


########################################################################################################################
# handleRequest: handles requests sent by browsers... 
#
#
sub handleRequest {
  
  open(TF, "$tracefile") || die "Trace file not defined or not readable - please specify with -f switch : $!";

  print Client <<"EOHEADER";
HTTP/1.0 200 OK
Server: WebMage/1.0
Expires: Fri, 01 Dec 1994 16:00:00 GMT
Content-type: text/html

EOHEADER

  my $curpos = 0;
  my ($readin, $length);

  Client->autoflush(1);

  seek(TF,0,0); # make sure we are at the start of the file we are tailing... 

  while (print Client "") { 

    $length = 1; # maximum number of bytes to read in at a time... 
    seek(TF, $curpos, 0);

    while (read(TF, $readin, $length)) {
     print Client "$readin";
    }

    $curpos = tell(TF);
    # chomp($date = `date`);
    # print Client "\n<br>Date = $date : Position = $curpos<br>\n";
    sleep(1);

  }

}
#
#
#
########################################################################################################################

########################################################################################################################
# usage: prints usage... 
#
#
sub usage {
  print "\n\n@_\n";
  print << "EOUSAGE"; 

Usage: $cmd [options]
       
   -p int   	# runs local server on port 'num'
   -f file      # file to follow... 
   -ps		# prints on the screen as they happen... (eg. number of requests handled)
   -about	# About this program

   eg. $cmd -p 6050 -f testfile.html -ps

EOUSAGE
  exit(0);
}
#
#
#
########################################################################################################################

########################################################################################################################
#
#
#
sub about {
  print <<"EOABOUT";

  WebMage version $version
  -------------------------------

  This program lets lots of clients (browsers) connect to it simultaneously, 
  and as soon as they connect, it sends them the contents of the 'tailfile'
  (the file we have specified we want to tail/follow). After that, it keeps 
  the connection open and if the tailfile has grown it almost instantaneously
  sends the additions to all the clients that are connected. The clients usually 
  never close the connection as we keep sending them a null string every second 
  anyway so that they don't timeout even if there is no updates for quite a while! 
  Its really good for doing 'live' stuff though. You could do a similar thing with 
  cgi, except that you could experience load problems on the server! I've tested 
  this scripts with dozens of clients connected simultaneously without any load 
  problems, and it seemed we could accomodate hundreds, maybe even thousands(?)
  more :-) 

  Please mail comments/suggestions to simran\@cse.unsw.edu.au

EOABOUT
  exit(0);
}
#
#
#
########################################################################################################################

