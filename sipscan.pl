#!/usr/bin/perl
# -=-=-=-
# SipScan
# -=-=-=-
#
# Sipscan works sending and waiting well-formed SIP packages. For example, Nmap
# is a great tool for scanning networks, but over UDP it is better and faster 
# to send well-formed SIP packages and wait valid responses.
# Sipscan tries, by default, to connect over the UDP protocol. If the connection
# fails, it will try over TCP. You can also force to use only over UDP or TCP.
#
# Pepelux <pepeluxx@gmail.com>
 
use warnings;
use strict;
use IO::Socket;
use IO::Socket::Timeout;
use NetAddr::IP;
use threads;
use threads::shared;
use Getopt::Long;
use Digest::MD5;
use DBI;

my $useragent = 'pplsip';
my $version;
 
my $maxthreads = 300;
 
my $threads : shared = 0;
my @range;
my @results;
 
my $host = '';		# host
my $lport = '';	# local port
my $dport = '';	# destination port
my $from = '';		# source number
my $to = '';		# destination number
my $method = '';	# method to use (INVITE, REGISTER, OPTIONS)
my $v = 0;		# verbose mode
my $vv = 0;		# more verbose
my $nolog = 0;
my $user = '';		# auth user
my $proto = '';	# protocol
my $withdb = 0;

my $abort = 0;

my $to_ip = '';
my $from_ip = '';

my $versionfile = 'version';
open(my $fh, '<:encoding(UTF-8)', $versionfile)
  or die "Could not open file '$versionfile' $!";
 
while (my $row = <$fh>) {
  chomp $row;
  $version = $row;
}
	
my $database = "sippts.db";
my $database_empty = "sippts_empty.db";

mkdir ("tmp") if (! -d "tmp");
my $tmpfile = "tmp/sipscan".time().".txt";

unless (-e $database || -e $database_empty) {
	die("Database $database not found\n\n");
}

system("cp $database_empty $database") if (! -e $database);
	
my $db = DBI->connect("dbi:SQLite:dbname=$database","","") or die $DBI::errstr;
my $hostsid = last_id();

open(OUTPUT,">$tmpfile");
 
OUTPUT->autoflush(1);
STDOUT->autoflush(1);

$SIG{INT} = \&interrupt;

sub init() {
    my $pini;
    my $pfin;
 
    # check params
    my $result = GetOptions ("h=s" => \$host,
				"m=s" => \$method,
				"d=s" => \$to,
				"s=s" => \$from,
				"ip=s" => \$from_ip,
				"u=s" => \$user,
				"l=s" => \$lport,
				"r=s" => \$dport,
				"proto=s" => \$proto,
				"db+" => \$withdb,
				"nolog+" => \$nolog,
				"ua=s" => \$useragent,
				"v+" => \$v,
				"vv+" => \$vv);
 
	help() if ($host eq "");
	check_version();
 
	$lport = "5070" if ($lport eq "");
	$dport = "5060" if ($dport eq "");
	$user = "100" if ($user eq "");
	$from = $user if ($from eq "");
	$to = $user if ($to eq "");
	$proto = lc($proto);
	$proto = "all" if ($proto ne "tcp" && $proto ne "udp");

	$method = uc($method);
	$method = "OPTIONS" if ($method eq "");
 
	my @hostlist;

	if ($host =~ /\,/) {
		@hostlist = split(/\,/, $host);

		foreach(@hostlist) {
			my $line = $_;

			if ($line =~ /\-/) {
				my $ip = $line;

				$ip =~ /([0-9|\.]*)-([0-9|\.]*)/;
				my $ipini = $1;
				my $ipfin = $2;

				my $ip2 = $ipini;
				$ip2 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
				my $ip2_1 = int($1);
				my $ip2_2 = int($2);
				my $ip2_3 = int($3);
				my $ip2_4 = int($4);

				my $ip3 = $ipfin;
				$ip3 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
				my $ip3_1 = int($1);
				my $ip3_2 = int($2);
				my $ip3_3 = int($3);
				my $ip3_4 = int($4);

				for (my $i1 = $ip2_1; $i1 <= $ip3_1; $i1++) {
					for (my $i2 = $ip2_2; $i2 <= $ip3_2; $i2++) {
						for (my $i3 = $ip2_3; $i3 <= $ip3_3; $i3++) {
							for (my $i4 = $ip2_4; $i4 <= $ip3_4; $i4++) {
								$ip = "$i1.$i2.$i3.$i4";
								push @range, $ip;
							}
				
							$ip2_4 = 1;
						}
				
						$ip2_3 = 1;
					}
				
					$ip2_2 = 1;
				}
			}
			else {
				my $ip = new NetAddr::IP($line);

				if ($ip < $ip->broadcast) {
					$ip++;

					while ($ip < $ip->broadcast) {
						my $ip2 = $ip;
						$ip2 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
						$ip2 = "$1.$2.$3.$4";
						push @range, $ip2;
						$ip++;
					}
				}
				else {
					push @range, $line;
				}
			}
		}
	}
	else {
		if ($host =~ /\-/) {
			my $ip = $host;

			$ip =~ /([0-9|\.]*)-([0-9|\.]*)/;
			my $ipini = $1;
			my $ipfin = $2;

			my $ip2 = $ipini;
			$ip2 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
			my $ip2_1 = int($1);
			my $ip2_2 = int($2);
			my $ip2_3 = int($3);
			my $ip2_4 = int($4);

			my $ip3 = $ipfin;
			$ip3 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
			my $ip3_1 = int($1);
			my $ip3_2 = int($2);
			my $ip3_3 = int($3);
			my $ip3_4 = int($4);

			for (my $i1 = $ip2_1; $i1 <= $ip3_1; $i1++) {
				for (my $i2 = $ip2_2; $i2 <= $ip3_2; $i2++) {
					for (my $i3 = $ip2_3; $i3 <= $ip3_3; $i3++) {
						for (my $i4 = $ip2_4; $i4 <= $ip3_4; $i4++) {
							$ip = "$i1.$i2.$i3.$i4";
							push @range, $ip;
						}
					}
				}
			}
		}
		else {
			my $ip = new NetAddr::IP($host);

			if ($ip < $ip->broadcast) {
				$ip++;

				while ($ip < $ip->broadcast) {
					my $ip2 = $ip;
					$ip2 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
					$ip2 = "$1.$2.$3.$4";
					push @range, $ip2;
					$ip++;
				}
			}
			else {
				push @range, $host;
			}
		}
	}

	if ($dport =~ /\-/) {
		$dport =~ /([0-9]*)-([0-9]*)/;
		$pini = $1;
		$pfin = $2;
	}
	else {
		$pini = $dport;
		$pfin = $dport;
	}

	my $nhost = @range;
 	my @arrow = ("|", "/", "-", "\\");
	my $cont = 0;

	for (my $i = 0; $i <= $nhost; $i++) {
		for (my $j = $pini; $j <= $pfin; $j++) {
			while (1) {
				if ($threads < $maxthreads) {
					last unless defined($range[$i]);
					my $csec = 1;
					$from_ip = $range[$i] if ($from_ip eq "");
					print "\r[".$arrow[$cont]."] Scanning ".$range[$i].":$j ...";
					my $thr = threads->new(\&scan, $range[$i], $from_ip, $lport, $j, $from, $to, $csec, $user, $proto);
					$thr->detach();
					$cont++;
					$cont = 0 if ($cont > 3);

					last;
				}
				else {
					sleep(1);
				}
			}
		}
	}

	sleep(1);

	close(OUTPUT);

	showres();
	unlink($tmpfile);

	exit;
}

sub save {
	my $line = shift;

	$line =~ s/\n//g;
	my @lines = split (/\t/, $line);
	my $sth = $db->prepare("SELECT id FROM hosts WHERE host='".$lines[0]."'") or die "Couldn't prepare statement: " . $db->errstr;
	$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
	my @data = $sth->fetchrow_array();
	my $sql;
	$sth->finish;

	$lines[4] = '' if !($lines[4]);

	if ($#data < 0) {
		$sql = "INSERT INTO hosts (id, host, port, proto, useragent, web) VALUES ($hostsid, '".$lines[0]."', ".$lines[1].", '".$lines[2]."', '".$lines[3]."','".$lines[4]."')";
		$db->do($sql);
		$hostsid = $db->func('last_insert_rowid') + 1;
	}
	else {
		$sql = "UPDATE hosts SET port=".$lines[1].", proto='".$lines[2]."', useragent='".$lines[3]."', web='".$lines[4]."' WHERE host='".$lines[0]."'";
		$db->do($sql);
	}
}

sub last_id {
	my $sth = $db->prepare('SELECT id FROM hosts ORDER BY id DESC LIMIT 1') or die "Couldn't prepare statement: " . $db->errstr;
	$sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
	my @data = $sth->fetchrow_array();
	$sth->finish;
	if ($#data > -1) { return $data[0] + 1; }
	else { return 1; }
}

sub showres {
	open(OUTPUT, $tmpfile);
 
 	if ($nolog eq 0) {
	 	print "\nIP address\tPort\tProto\tUser-Agent\tWeb\n";
		print "==========\t====\t=====\t==========\t===\n";
	}

	my @results = <OUTPUT>;
	close (OUTPUT);

	@results = sort(@results);

	foreach(@results) {
		my $line = $_;
		print $line if ($nolog eq 0);
		save($line) if ($withdb eq 1);
	}

	print "\n";
}

sub interrupt {
	if ($abort eq 0) {
		$abort = 1;
		{lock($threads); $threads=$maxthreads;}

		print "Closing threads. Please wait ...\n";
		sleep(2);

		close(OUTPUT);

		showres();
		unlink($tmpfile);
	 
		exit;
	}
	else {
		print "Closing threads. Please wait ...\n\n";
	}
}

sub scan {
	my $to_ip = shift;
	my $from_ip = shift;
	my $lport = shift;
	my $dport = shift;
	my $from = shift;
	my $to = shift;
	my $csec = shift;
	my $user = shift;
	my $proto = shift;

	my $p = $proto;
	my $r = '';
	
	$p = "udp" if ($proto eq "all");
	$r = send_register($from_ip, $to_ip, $lport, $dport, $from, $to, $csec, $user, $p) if ($method eq "REGISTER");
	send_register($from_ip, $to_ip, $lport, $dport, $from, $to, $csec, $user, "tcp") if ($method eq "REGISTER" && $proto eq "all" && $r eq "");
	$r = send_invite($from_ip, $to_ip, $lport, $dport, $from, $to, $csec, $user, $p) if ($method eq "INVITE");
	send_invite($from_ip, $to_ip, $lport, $dport, $from, $to, $csec, $user, "tcp") if ($method eq "INVITE" && $proto eq "all" && $r eq "");
	$r = send_options($from_ip, $to_ip, $lport, $dport, $from, $to, $csec, $user, $p) if ($method eq "OPTIONS");
	send_options($from_ip, $to_ip, $lport, $dport, $from, $to, $csec, $user, "tcp") if ($method eq "OPTIONS" && $proto eq "all" && $r eq "");
	
}
 
# Send REGISTER message
sub send_register {
	{lock($threads);$threads++;}
 
	my $from_ip = shift;
	my $to_ip = shift;
	my $lport = shift;
	my $dport = shift;
	my $from = shift;
	my $to = shift;
	my $cseq = shift;
	my $user = shift;
	my $proto = shift;
	my $response = "";

	my $sc = new IO::Socket::INET->new(PeerPort=>$dport, Proto=>$proto, PeerAddr=>$to_ip, Timeout => 5);

	if ($sc) {
		IO::Socket::Timeout->enable_timeouts_on($sc);
		$sc->read_timeout(0.5);
		$sc->enable_timeout;
		$lport = $sc->sockport();

		my $branch = &generate_random_string(71, 0);
		my $callid = &generate_random_string(32, 1);
	
		my $msg = "REGISTER sip:".$to_ip." SIP/2.0\r\n";
		$msg .= "Via: SIP/2.0/".uc($proto)." $from_ip:$lport;branch=$branch\r\n";
		$msg .= "From: <sip:".$user."@".$to_ip.">;tag=0c26cd11\r\n";
		$msg .= "To: <sip:".$user."@".$to_ip.">\r\n";
		$msg .= "Contact: <sip:".$user."@".$from_ip.":$lport;transport=$proto>\r\n";
		$msg .= "Call-ID: ".$callid."\r\n";
		$msg .= "CSeq: $cseq REGISTER\r\n";
		$msg .= "User-Agent: $useragent\r\n";
		$msg .= "Max-Forwards: 70\r\n";
		$msg .= "Allow: INVITE,ACK,CANCEL,BYE,NOTIFY,REFER,OPTIONS,INFO,SUBSCRIBE,UPDATE,PRACK,MESSAGE\r\n";
		$msg .= "Expires: 10\r\n";
		$msg .= "Content-Length: 0\r\n\r\n";

		my $data = "";
		my $server = "";
		my $ua = "";
		my $line = "";

		print $sc $msg;

		print "[+] $to_ip:$dport/$proto - Sending REGISTER $from => $to\n" if ($v eq 1);
		print "[+] $to_ip:$dport/$proto - Sending:\n=======\n$msg" if ($vv eq 1);

		use Errno qw(ETIMEDOUT EWOULDBLOCK);
		
		LOOP: {
			while (<$sc>) {
				if ( 0+$! == ETIMEDOUT || 0+$! == EWOULDBLOCK ) {
					{lock($threads);$threads--;}
					return "";
				}

				$line = $_;
			
				if ($line =~ /^SIP\/2.0/ && ($response eq "" || $response =~ /^1/)) {
					$line =~ /^SIP\/2.0\s(.+)\r\n/;
				
					if ($1) { $response = $1; }
				}

				if ($line =~ /[Ss]erver/ && $server eq "") {
					$line =~ /[Ss]erver\:\s(.+)\r\n/;
 
					$server = $1 if ($1);
				}

				if ($line =~ /[Uu]ser\-[Aa]gent/ && $ua eq "") {
					$line =~ /[Uu]ser\-[Aa]gent\:\s(.+)\r\n/;
 
					$ua = $1 if ($1);
				}

				$data .= $line;
 
				if ($line =~ /^\r\n/) {
					print "[-] $response\n" if ($v eq 1);
					print "Receiving:\n=========\n$data" if ($vv eq 1);

					last LOOP if ($response !~ /^1/);
				}
			}
		}
    
		if ($data ne "") {
			if ($server eq "") {
				$server = $ua;
			}
			else {
				if ($ua ne "") {
					$server .= " - $ua";
				}
			}

			$server = "Unknown" if ($server eq "");
			print OUTPUT "$to_ip\t$dport\t$proto\t$server\n";
		}
	}
	
	{lock($threads);$threads--;}
	
	return $response;
}

# Send INVITE message
sub send_invite {
	{lock($threads);$threads++;}
 
	my $from_ip = shift;
	my $to_ip = shift;
	my $lport = shift;
	my $dport = shift;
	my $from = shift;
	my $to = shift;
	my $cseq = shift;
	my $user = shift;
	my $proto = shift;
	my $response = "";

	my $sc = new IO::Socket::INET->new(PeerPort=>$dport, Proto=>$proto, PeerAddr=>$to_ip, Timeout => 5);

	if ($sc) {
		IO::Socket::Timeout->enable_timeouts_on($sc);
		$sc->read_timeout(0.5);
		$sc->enable_timeout;
		$lport = $sc->sockport();

		my $branch = &generate_random_string(71, 0);
		my $callid = &generate_random_string(32, 1);
	
		my $msg = "INVITE sip:".$to."@".$to_ip." SIP/2.0\r\n";
		$msg .= "Via: SIP/2.0/".uc($proto)." $from_ip:$lport;branch=$branch\r\n";
		$msg .= "From: \"$from\" <sip:".$user."@".$to_ip.">;tag=0c26cd11\r\n";
		$msg .= "To: <sip:".$to."@".$to_ip.">\r\n";
		$msg .= "Contact: <sip:".$from."@".$from_ip.":$lport;transport=$proto>\r\n";
		$msg .= "Supported: replaces, timer, path\r\n";
		$msg .= "P-Early-Media: Supported\r\n";
		$msg .= "Call-ID: $callid\r\n";
		$msg .= "CSeq: $cseq INVITE\r\n";
		$msg .= "User-Agent: $useragent\r\n";
		$msg .= "Max-Forwards: 70\r\n";
		$msg .= "Allow: INVITE,ACK,CANCEL,BYE,NOTIFY,REFER,OPTIONS,INFO,SUBSCRIBE,UPDATE,PRACK,MESSAGE\r\n";
		$msg .= "Content-Type: application/sdp\r\n";

		my $sdp .= "v=0\r\n";
		$sdp .= "o=anonymous 1312841870 1312841870 IN IP4 $from_ip\r\n";
		$sdp .= "s=session\r\n";
		$sdp .= "c=IN IP4 $from_ip\r\n";
		$sdp .= "t=0 0\r\n";
		$sdp .= "m=audio 2362 RTP/AVP 0\r\n";
		$sdp .= "a=rtpmap:18 G729/8000\r\n";
		$sdp .= "a=rtpmap:0 PCMU/8000\r\n";
		$sdp .= "a=rtpmap:8 PCMA/8000\r\n\r\n";

		$msg .= "Content-Length: ".length($sdp)."\r\n\r\n";
		$msg .= $sdp;

		my $data = "";
		my $server = "";
		my $ua = "";
		my $line = "";

		print $sc $msg;

		print "[+] $to_ip:$dport/$proto - Sending INVITE $from => $to\n" if ($v eq 1);
		print "[+] $to_ip:$dport/$proto - Sending:\n=======\n$msg" if ($vv eq 1);

		use Errno qw(ETIMEDOUT EWOULDBLOCK);
		
		LOOP: {
			while (<$sc>) {
				if ( 0+$! == ETIMEDOUT || 0+$! == EWOULDBLOCK ) {
					{lock($threads);$threads--;}
					return "";
				}

				$line = $_;
			
				if ($line =~ /^SIP\/2.0/ && ($response eq "" || $response =~ /^1/)) {
					$line =~ /^SIP\/2.0\s(.+)\r\n/;
				
					if ($1) { $response = $1; }
				}

				if ($line =~ /[Ss]erver/ && $server eq "") {
					$line =~ /[Ss]erver\:\s(.+)\r\n/;
 
					$server = $1 if ($1);
				}

				if ($line =~ /[Uu]ser\-[Aa]gent/ && $ua eq "") {
					$line =~ /[Uu]ser\-[Aa]gent\:\s(.+)\r\n/;
 
					$ua = $1 if ($1);
				}

				$data .= $line;
 
				if ($line =~ /^\r\n/) {
					print "[-] $response\n" if ($v eq 1);
					print "Receiving:\n=========\n$data" if ($vv eq 1);
				}
			}
		}
    
		if ($data ne "") {
			if ($server eq "") {
				$server = $ua;
			}
			else {
				if ($ua ne "") {
					$server .= " - $ua";
				}
			}

			$server = "Unknown" if ($server eq "");
			print OUTPUT "$to_ip\t$dport\t$proto\t$server\n";
		}
	}
	
	{lock($threads);$threads--;}
	
	return $response;
}

# Send OPTIONS message
sub send_options {
	{lock($threads);$threads++;}
 
	my $from_ip = shift;
	my $to_ip = shift;
	my $lport = shift;
	my $dport = shift;
	my $from = shift;
	my $to = shift;
	my $cseq = shift;
	my $user = shift;
	my $proto = shift;
	my $response = "";

	my $sc = new IO::Socket::INET->new(PeerPort=>$dport, Proto=>$proto, PeerAddr=>$to_ip, Timeout => 5);

	if ($sc) {
		IO::Socket::Timeout->enable_timeouts_on($sc);
		$sc->read_timeout(0.5);
		$sc->enable_timeout;
		$lport = $sc->sockport();

		my $branch = &generate_random_string(71, 0);
		my $callid = &generate_random_string(32, 1);
	
		my $msg = "OPTIONS sip:".$to."@".$to_ip." SIP/2.0\r\n";
		$msg .= "Via: SIP/2.0/".uc($proto)." $from_ip:$lport;branch=$branch\r\n";
		$msg .= "From: <sip:".$user."@".$to_ip.">;tag=0c26cd11\r\n";
		$msg .= "To: <sip:".$user."@".$to_ip.">\r\n";
		$msg .= "Contact: <sip:".$user."@".$from_ip.":$lport;transport=$proto>\r\n";
		$msg .= "Call-ID: $callid\r\n";
		$msg .= "CSeq: $cseq OPTIONS\r\n";
		$msg .= "User-Agent: $useragent\r\n";
		$msg .= "Max-Forwards: 70\r\n";
		$msg .= "Allow: INVITE,ACK,CANCEL,BYE,NOTIFY,REFER,OPTIONS,INFO,SUBSCRIBE,UPDATE,PRACK,MESSAGE\r\n";
		$msg .= "Content-Length: 0\r\n\r\n";

		my $data = "";
		my $server = "";
		my $ua = "";
		my $line = "";

		print $sc $msg;

		print "[+] $to_ip:$dport/$proto - Sending OPTIONS $from => $to\n" if ($v eq 1);
		print "[+] $to_ip:$dport/$proto - Sending:\n=======\n$msg" if ($vv eq 1);

		use Errno qw(ETIMEDOUT EWOULDBLOCK);
		
		LOOP: {
			while (<$sc>) {
				if ( 0+$! == ETIMEDOUT || 0+$! == EWOULDBLOCK ) {
					{lock($threads);$threads--;}
					return "";
				}
				
				$line = $_;
			
				if ($line =~ /^SIP\/2.0/ && ($response eq "" || $response =~ /^1/)) {
					$line =~ /^SIP\/2.0\s(.+)\r\n/;
				
					if ($1) { $response = $1; }
				}

				if ($line =~ /[Ss]erver/ && $server eq "") {
					$line =~ /[Ss]erver\:\s(.+)\r\n/;
 
					$server = $1 if ($1);
				}

				if ($line =~ /[Uu]ser\-[Aa]gent/ && $ua eq "") {
					$line =~ /[Uu]ser\-[Aa]gent\:\s(.+)\r\n/;
 
					$ua = $1 if ($1);
				}

				$data .= $line;
 
				if ($line =~ /^\r\n/) {
					print "[-] $response\n" if ($v eq 1);
					print "Receiving:\n=========\n$data" if ($vv eq 1);

					last LOOP if ($response !~ /^1/);
				}
			}

			last LOOP;
		}

		if ($data ne "") {
			if ($server eq "") {
				$server = $ua;
			}
			else {
				if ($ua ne "") {
					$server .= " - $ua";
				}
			}

			$server = "Unknown   " if ($server eq "");
			my $webfound = 0;
			print OUTPUT "$to_ip\t$dport\t$proto\t$server";

			my $sc2 = new IO::Socket::INET->new(PeerPort=>80, Proto=>'tcp', PeerAddr=>$to_ip, Timeout => 10);
			if ($sc2) { $webfound = 1; print OUTPUT "\t80/tcp"; }
			else {
				$sc2 = new IO::Socket::INET->new(PeerPort=>81, Proto=>'tcp', PeerAddr=>$to_ip, Timeout => 10);
				if ($sc2) { $webfound = 1; print OUTPUT "\t81/tcp"; }
				else {
					$sc2 = new IO::Socket::INET->new(PeerPort=>8000, Proto=>'tcp', PeerAddr=>$to_ip, Timeout => 10);
					if ($sc2) { $webfound = 1; print OUTPUT "\t8000/tcp"; }
					else {
						$sc2 = new IO::Socket::INET->new(PeerPort=>8080, Proto=>'tcp', PeerAddr=>$to_ip, Timeout => 10);
						if ($sc2) { $webfound = 1; print OUTPUT "\t8080/tcp"; }
						else {
							$sc2 = new IO::Socket::INET->new(PeerPort=>443, Proto=>'tcp', PeerAddr=>$to_ip, Timeout => 10);
							if ($sc2) { $webfound = 1; print OUTPUT "\t443/tcp"; }
							else { $webfound = 1; print OUTPUT "\t0"; }
						}
					}
				}
			}

			print OUTPUT "\n";
		}
	}
	
	{lock($threads);$threads--;}

	return $response;
}

 
sub generate_random_string {
    my $length_of_randomstring = shift;
    my $only_hex = shift;
    my @chars;
 
    if ($only_hex == 0) {
        @chars = ('a'..'z','0'..'9');
    }
    else {
        @chars = ('a'..'f','0'..'9');
    }
    my $random_string;
    foreach (1..$length_of_randomstring) {
        $random_string.=$chars[rand @chars];
    }
    return $random_string;
}
 
sub check_version {
	my $v = `curl -s https://raw.githubusercontent.com/Pepelux/sippts/master/version`;
	$v =~ s/\n//g;

	if ($v ne $version) {	
		print "The current version ($version) is outdated. There is a new version ($v). Please update:\n";
		print "https://github.com/Pepelux/sippts\n";
	}
}

sub help {
    print qq{
SipSCAN - by Pepelux <pepeluxx\@gmail.com>
-------

Usage: perl $0 -h <host> [options]
 
== Options ==
-m  <string>     = Method: REGISTER/INVITE/OPTIONS (default: OPTIONS)
-u  <string>     = Username
-s  <integer>    = Source number (CallerID) (default: 100)
-d  <integer>    = Destination number (default: 100)
-r  <integer>    = Remote port (default: 5060)
-proto <string>  = Protocol (udp, tcp or all (both of them) - By default: ALL)
-ip <string>     = Source IP (by default it is the same as host)
-ua <string>     = Customize the UserAgent
-db              = Save results into database (sippts.db)
-nolog           = Don't show anything on the console
-v               = Verbose (trace information)
-vv              = More verbose (more detailed trace)
 
== Examples ==
\$perl $0 -h 192.168.0.1
\tTo search SIP services on 192.168.0.1 port 5060 (using OPTIONS method)
\$perl $0 -h 192.168.0.1,192.168.2.0/24.192.168.3.1-192.168.20.200
\tTo search several ranges
\$perl $0 -h 192.168.0.1 -m INVITE
\tTo search SIP services on 192.168.0.1 port 5060 (using INVITE method)
\$perl $0 -h 192.168.0.0/24 -v -t tcp
\tTo search SIP services on 192.168.0.0 network by TCP connection (using OPTIONS method)
\$perl $0 -h 192.168.0.1-192.168.0.100 -r 5060-5070 -vv
\tTo search SIP services on 192.168.0.100 ports from 5060 to 5070 (using OPTIONS method)

};
 
    exit 1;
}
 
init();
