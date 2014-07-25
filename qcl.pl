#!/usr/bin/perl

#
# qcl.pl
# $Date$
# $Revision$
#
# QNX QCONN service provider client.
#
# Copyright (c) 2009 Kaloyan Tenchov
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# TODO:
#   - Parse error messages of file service.
#   - Allow multiple sources of put and get commands.
#   - Recursive deletion of directories.
#   - ls command.
#   - ps command.
#   - Handle console input.
#

use warnings;
use strict;

use Getopt::Long qw(:config auto_version);
use Pod::Usage;
use Net::Telnet;
use Fcntl;
use Fcntl ':mode';



use vars qw($VERSION);
$VERSION = '1.0';

my $opt_help = 0;
my $opt_man = 0;
my $opt_host = 'localhost';
my $opt_port = 8000;
my $opt_mode = S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH;

my $command = 'info';
my $get_buf_size = 2*1024;      # There are problems when reading files with buffer size bigger than 2kB
my $put_buf_size = 16*1024;
my $q;


sub get_basename
{
    $_[0] =~ /([^\/\\]+)$/o;
    return $1;
}


sub str_to_int
{
    return oct($_[0]) if ($_[0] =~ /^0/);
    return int($_[0]);
}


sub get_service_version
{
    my $service = $_[0];
    my $version = -1;

    my @lines = $q->cmd('versions ' . $service);
    $version = int($1) if ($#lines >= 0 && $lines[0] =~ /^(\d+)/o);

    return $version;
}


sub cmd_info
{
    my @lines = $q->cmd('info');
    for (sort(split(/\s+/o, $lines[0])))
    {
        print("$_\n") if ('' ne $_);
    }

    $q->print('quit');
    return 0;
}


sub cmd_versions
{
    my @lines = $q->cmd('versions ?');
    my $versions = '';
    $versions = $1 if ($#lines >= 0 && $lines[0] =~ /^versions: (.+)$/o);
    for (sort(split(/\s+/o, $versions)))
    {
        print("$_\n") if ('' ne $_);
    }

    $q->print('quit');
    return 0;
}


sub cmd_exec
{
    my @lines;

    if ($#ARGV < 0)
    {
        print("Command not specified.\n");
        $q->print('quit');
        return 1;
    }

    # Check launcher service version
    $_ = get_service_version('launcher');
    if ($_ < 256)
    {
        print("Unsupported launcher service version.\n");
        $q->print('quit');
        return 3;
    }

    my $command = shift(@ARGV);
    my $command_name = get_basename($command);
    my $args = join(' ', @ARGV);
    $args = ' ' . $args if ('' ne $args);

    # Switch to launcher service
    $q->prompt('/<qconn-launcher>\s*$/o');
    @lines = $q->cmd('service launcher');
    if ($#lines < 0 || $lines[0] !~ /^OK$/o)
    {
        print("Failed to switch to launcher service.\n");
        $q->print('quit');
        return 3;
    }

    # Change to root directory
    @lines = $q->cmd('chdir /');
    if ($#lines < 0 || $lines[0] !~ /^OK$/o)
    {
        print("Failed to change directory.\n");
        $q->print('quit');
        return 3;
    }

    # Load executable
    @lines = $q->cmd("start/flags 8000 $command $command_name$args");
    if ($#lines < 0 || $lines[0] !~ /^OK \d+$/o)
    {
        print("Failed to execute command.\n");
        $q->print('quit');
        return 3;
    }

    # Start process
    $q->print('continue');      # Do not use cmd() to avaoid waiting for prompt.
    my $line = $q->getline();
    if ($line !~ /^OK$/o)
    {
        print("Failed to execute command.\n");
        $q->print('quit');
        return 3;
    }

    # Pipe output to stdout
    $q->telnetmode(0);
    my $buf;
    while ($buf = $q->get())
    {
        print($buf);
    }

    return 0;
}


sub get_mode
{
    my $spec = $_[0];

    my $cmd;
    my @lines;

    $cmd = sprintf('o:%s:%x', $spec, O_RDONLY);
    @lines = $q->cmd($cmd);
    return -1 if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f-]+):([0-9a-f-]+):([0-9a-f-]+):\"(.+)\"$/oi || $4 ne $spec);
    my $f = hex($1);
    my $mode = hex($2);

    $cmd = sprintf('c:%x', $f);
    @lines = $q->cmd($cmd);
    return -1 if ($#lines < 0 || $lines[0] !~ /^o\s*$/o);

    return $mode;
}


sub switch_to_file_service
{
    # Check file service version
    $_ = get_service_version('file');
    if ($_ < 256)
    {
        print("Unsupported file service version $_.\n");
        $q->print('quit');
        return 3;
    }

    # Switch to file service
    $q->prompt('/<qconn-file>\s*$/o');
    my @lines = $q->cmd('service file');
    if ($#lines < 0 || $lines[0] !~ /^OK$/o)
    {
        print("Failed to switch to file service.\n");
        $q->print('quit');
        return 3;
    }

    return 0;
}


sub cmd_put
{
    my $cmd;
    my @lines;
    my $res = 0;

    if ($#ARGV < 1)
    {
        print("Source and target not specified.\n");
        $q->print('quit');
        return 1;
    }

    my $source = shift(@ARGV);
    my $target = shift(@ARGV);

    # Switch to file service
    $_ = switch_to_file_service();
    return $_ if ($_ != 0);

    # Check if target exists and is a directory
    my $mode = get_mode($target);
    $target .= '/' . get_basename($source) if (Fcntl::S_ISDIR($mode));

    # Open source file
    my $sf;
    if (!open($sf, '<', $source))
    {
        print("Failed to open source file $source. $!\n");
        $q->print('quit');
        return 1;
    }
    binmode($sf);

    # Create target file
    $cmd = sprintf("o:\"%s\":%x:%x", $target, O_CREAT|O_TRUNC|O_WRONLY, $opt_mode);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f-]+):([0-9a-f-]+):([0-9a-f-]+):\"(.+)\"$/oi || $4 ne $target)
    {
        print("Failed to create target file $target.\n");
        close($sf);
        $q->print('quit');
        return 3;
    }

    # Get target file descriptor
    my $tf = hex($1);

    $q->binmode(1);
    $q->telnetmode(0);

    my $offs = 0;
    my $numread = 1;        # last statement cannot be used with do-while blocks
    my $buf;
    while ($numread > 0)
    {
        $numread = read($sf, $buf, $put_buf_size);
        if (!defined($numread))
        {
            print("Failed reading from source file. $!\n");
            $res = 3;
            last;
        }

        if ($numread > 0)
        {
            # Send write command without waiting for prompt
            $cmd = sprintf('w:%x:%x:%x', $tf, $offs, $numread);
            $q->print($cmd);

            # Send buffer contents
            $q->put($buf);

            # Get response line
            my $line = $q->getline();
            if ($line !~ /^o:([0-9a-f-]+):([0-9a-f-]+)/oi || hex($1) != $numread)
            {
                print("Failed writing to target file.\n");
                $res = 3;
                last;
            }

            # Wait for file service prompt
            $q->waitfor($q->prompt);

            $offs += $numread;
        }
    }

    # Close target file
    $cmd = sprintf('c:%x', $tf);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o\s*$/o)
    {
        print("Failed to properly close target file.\n");
        $res = 3;
    }

    # Send quit command to file service
    $q->print('q');

    # Close source file
    close($sf);

    return $res;
}


sub cmd_get
{
    my $cmd;
    my @lines;
    my $res = 0;

    if ($#ARGV < 1)
    {
        print("Source and target not specified.\n");
        $q->print('quit');
        return 1;
    }

    my $source = shift(@ARGV);
    my $target = shift(@ARGV);

    # Switch to file service
    $_ = switch_to_file_service();
    return $_ if ($_ != 0);

    # Open source file
    $cmd = sprintf("o:\"%s\":%x", $source, O_RDONLY);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f-]+):([0-9a-f-]+):([0-9a-f-]+):\"(.+)\"$/oi || $4 ne $source)
    {
        print("Failed to open source file $source.\n");
        $q->print('q');
        return 3;
    }

    # Get source file descriptor and size
    my $sf = hex($1);
    my $total_size = hex($3);

    # Check if target exists and is a directory
    $target .= '/' . get_basename($source) if (-d $target);

    # Open target file
    my $tf;
    if (!open($tf, '>', $target))
    {
        print("Failed to create target file $target. $!\n");
        $q->print('q');
        return 1;
    }
    binmode($tf);

    $q->binmode(1);
    $q->telnetmode(0);

    my $offs = 0;
    my $numread = 1;        # last statement cannot be used with do-while blocks
    my $buf;
    my $line;
    while (!$q->eof() && $numread > 0)
    {
        # Send read command without waiting for prompt
        $cmd = sprintf('r:%x:%x:%x', $sf, $offs, $get_buf_size);
        $q->print($cmd);

        # Get response line
        $line = $q->getline();
        if ($line !~ /^o:([0-9a-f-]+):[0-9a-f-]+:[0-9a-f-]+/oi)
        {
            print("Failed reading from source file. $line\n");
            $res = 3;
            last;
        }
        $numread = hex($1);

        # Retrieve buffer contents and wait for prompt
        $buf = '';
        while (!$q->eof() && (length($buf) < $numread || $buf !~ /<qconn-file>\s*$/so))
        {
            $buf .= $q->get();
        }

        $buf = substr($buf, 0, $numread);

        # Write to target
        if ($numread > 0)
        {
            if (!print($tf $buf))
            {
                print("Failed writing to target file.\n");
                $res = 3;
                last;
            }
            $offs += $numread;
        }
    }

    # Check numbe of bytes written
    if ($offs != $total_size)
    {
        print("Copying failed.\n");
        $res = 3;
    }

    # Close source file
    $cmd = sprintf('c:%x', $sf);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o\s*$/o)
    {
        print("Failed to properly close source file.\n");
        $res = 3;
    }

    # Send quit command to file service
    $q->print('q');

    close($tf);

    return $res;
}


sub cmd_rm
{
    my $cmd;
    my @lines;
    my $res = 0;

    if ($#ARGV < 0)
    {
        print("Target not specified.\n");
        $q->print('quit');
        return 1;
    }

    my $target = shift(@ARGV);

    # Switch to file service
    $_ = switch_to_file_service();
    return $_ if ($_ != 0);

    # Delete target
    $cmd = sprintf("d:\"%s\":1", $target);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o\s*$/o)
    {
        print("No such file or directory or operation failed.\n");
        $res = 3;
    }

    # Send quit command to file service
    $q->print('q');

    return $res;
}


sub cmd_mkdir
{
    my $cmd;
    my @lines;
    my $res = 0;

    if ($#ARGV < 0)
    {
        print("Target not specified.\n");
        $q->print('quit');
        return 1;
    }

    my $target = shift(@ARGV);

    # Switch to file service
    $_ = switch_to_file_service();
    return $_ if ($_ != 0);

    # Create target directory
    $cmd = sprintf("o:\"%s\":%x:%x", $target, O_CREAT|O_WRONLY, S_IFDIR|S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH);
    @lines = $q->cmd($cmd);
    print @lines;
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f-]+):([0-9a-f-]+):([0-9a-f-]+):\"(.+)\"$/oi || $4 ne $target)
    {
        print("Failed to create target directory $target.\n");
        $q->print('quit');
        return 3;
    }

    # Send quit command to file service
    $q->print('q');

    return $res;
}


sub cmd_chmod
{
    my $cmd;
    my @lines;
    my $res = 0;
    my $open_mode = O_RDWR;

    if ($#ARGV < 0)
    {
        print("Target not specified.\n");
        $q->print('quit');
        return 1;
    }

    my $target = shift(@ARGV);

    # Switch to file service
    $_ = switch_to_file_service();
    return $_ if ($_ != 0);

    # Check whether the target is a directory
    my $mode = get_mode($target);
    $open_mode = S_IFDIR if (Fcntl::S_ISDIR($mode));

    # Open target
    $cmd = sprintf("o:\"%s\":%x", $target, $open_mode);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f-]+):([0-9a-f-]+):([0-9a-f-]+):\"(.+)\"$/oi || $4 ne $target)
    {
        print("Failed to open target $target.\n");
        $q->print('q');
        return 3;
    }

    # Get source file descriptor and size
    my $tf = hex($1);

    # Set permissons
    $cmd = sprintf("a:%x:%x", $tf, $opt_mode);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o\s*$/o)
    {
        print("Failed to properly close target.\n");
        $res = 3;
    }

    # Close target file
    $cmd = sprintf('c:%x', $tf);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o\s*$/o)
    {
        print("Failed to properly close target.\n");
        $res = 3;
    }

    # Send quit command to file service
    $q->print('q');

    return $res;
}


sub cmd_kill
{
    my $cmd;
    my @lines;
    my $res = 0;
    my $open_mode = O_RDWR;

    if ($#ARGV < 1)
    {
        print("Target and signal not specified.\n");
        $q->print('quit');
        return 1;
    }

    my $pid = str_to_int(shift(@ARGV));
    my $signal = str_to_int(shift(@ARGV));

    # Check cntl service version
    $_ = get_service_version('cntl');
    if ($_ < 256)
    {
        print("Unsupported cntl service version $_.\n");
        $q->print('quit');
        return 3;
    }

    # Switch to cntl service
    $q->prompt('/<qconn-cntl>\s*$/o');
    @lines = $q->cmd('service cntl');
    if ($#lines < 0 || $lines[0] !~ /^OK$/o)
    {
        print("Failed to switch to cntl service.\n");
        $q->print('quit');
        return 3;
    }

    # Send kill command
    $cmd = sprintf("kill %d %d", $pid, $signal);
    print "$cmd\n";
    @lines = $q->cmd($cmd);
    print @lines;
    if ($#lines < 0 || $lines[0] !~ /^ok\s*$/o)
    {
        print("No such process or operation failed.\n");
        $q->print('quit');
        return 3;
    }

    # Send quit command to file service
    $q->print('quit');

    return $res;
}


$| = 1;

# Process command-line
GetOptions
(
    'help|?' => \$opt_help,
    'man' => \$opt_man,
    'host=s' => \$opt_host,
    'port=i' => \$opt_host,
    'mode=s' => sub { $opt_mode = str_to_int($_[1]) & 0xFFF; }
) or pod2usage(2);

pod2usage(-exitstatus => 0, -verbose => 99, -sections => 'SYNOPSIS|OPTIONS|COMMANDS') if $opt_help;
pod2usage(-exitstatus => 0, -verbose => 2) if $opt_man;

# Define command
$command = shift(@ARGV) if ($#ARGV >= 0);
$command = lc($command);

# Create Net::Telnet object
$q = new Net::Telnet
(
    Timeout => 5,
    Errmode => 'return',
    Prompt => '/<qconn-broker>\s*$/o'
);

$q->option_callback(sub {});
$q->option_accept
(
    # FIXME
    #Do => Net::Telnet::TELOPT_LINEMODE,
    Dont => Net::Telnet::TELOPT_LINEMODE,
    Dont => Net::Telnet::TELOPT_ECHO,
);

# Debug
#$q->dump_log('io.log');
#$q->option_log('opt.log');

# Connect to QCONN server
if (!$q->open(Host => $opt_host, Port => $opt_port))
{
    print("Failed to connect to QCONN server at $opt_host:$opt_port.\n");
    exit(2);
}

# Wait for prompt and skip error message due to both linemode and echo Telnet options being refused
if (!$q->waitfor('/^QCONN$/o') ||
    !$q->waitfor($q->prompt) ||
    !$q->waitfor('/error linemode-or-echo-not-supported\s*/'))
{
    print("Invalid or no response from QCONN server.\n");
    $q->close();
    exit(3);
}

# Check broker version
if (get_service_version('broker') < 256)
{
    print("Unsupported broker version.\n");
    $q->close();
    exit(3);
}

# Process command

my $res = 1;

if ('info' eq $command)
{
    $res = cmd_info();
}
elsif ('versions' eq $command)
{
    $res = cmd_versions();
}
elsif ('exec' eq $command)
{
    $res = cmd_exec();
}
elsif ('put' eq $command)
{
    $res = cmd_put();
}
elsif ('get' eq $command)
{
    $res = cmd_get();
}
elsif ('rm' eq $command)
{
    $res = cmd_rm();
}
elsif ('mkdir' eq $command)
{
    $res = cmd_mkdir();
}
elsif ('chmod' eq $command)
{
    $res = cmd_chmod();
}
elsif ('kill' eq $command)
{
    $res = cmd_kill();
}
else
{
    print("Unknown command \"$command\".\n");
}

# Close connection to server
$q->close();

exit($res);


__END__

=head1 NAME

qcl.pl - QNX QCONN service provider client.

=head1 SYNOPSIS

qcl.pl [I<options>] [[--] I<command> [I<parameters>]]

=head1 COMMANDS

=over 8

=item B<info>

Retrieves system information for the target the QCONN server is running on.
This is the default command.

=item B<versions>

Retrieves a list of services supported by the QCONN server and their versions.

=item B<exec> I<command> [I<parameters>]

Executes the specified command on the target the QCONN server is running on.
The use of "--" in front of the command is encouraged to avoid parameter misinterpretation.

=item B<put> I<source> I<target>

Transfers the file specified as source to the target the QCONN server is running on.
The --mode option may be used to specify permissions for the file when it is created.

=item B<get> I<source> I<target>

Transfers the file specified as source from the target the QCONN server is running on.

=item B<rm> I<target>

Deletes the specified file or directory on the target the QCONN server is running on.

=item B<mkdir> I<target>

Creates the specified directory on the target the QCONN server is running on.

=item B<chmod> I<target>

Changes the permissions of the specified file or directory on the target the QCONN server
is running on. The permissions are specified with the --mode option.

=item B<kill> I<pid> I<signal>

Sends the specified signal to the process with the specified PID on the target the QCONN
server is running on.

=back

=head1 OPTIONS

=over 8

=item B<--host>=I<address>

Specifies QCONN server as hostname or IP address. Default is localhost.

=item B<--port>=I<port>

Specifies QCONN server TCP port. Default is 8000.

=item B<--mode>=I<permissions>

Specifies file permissions used with some commands. Default is 0666.

=item B<--version>

Prints program version.

=item B<--help>

Prints a brief help message.

=item B<--man>

Prints detailed program documentation.

=back

=head1 DESCRIPTION

qcl.pl is a Perl script working as a QNX QCONN service provider client. It allows
controlling a QCONN server from the command-line and automating certain development
activities for the QNX platform without using additional server applicaitons (e.g.
Telnet, FTP, SSH, etc.).

This script is far from complete and is not intended to replace the use of the
QNX Momentics IDE.

The Net::Telnet Perl module is required (L<http://search.cpan.org/~jrogers/Net-Telnet-3.03/lib/Net/Telnet.pm>).

=head1 EXAMPLES

Transferring a file to a QNX target:

    C:\qcl>perl qcl.pl --host=10.0.0.2 put test.zip /tmp

Retrieving a file from a QNX target:

    C:\qcl>perl qcl.pl --host=10.0.0.2 get /tmp/test.zip .

Transferring an application to a QNX target and executing it:

    C:\qcl>perl qcl.pl --host=10.0.0.2 --mode=0777 put hello /tmp
    C:\qcl>perl qcl.pl --host=10.0.0.2 exec /tmp/hello
    Hello World!

Executing an application on a QNX target:

    C:\qcl>perl qcl.pl --host=10.0.0.2 -- exec /bin/ls -l /usr
    total 168
    drwxrwxr-x 14 root      root           4096 Jun 04  2008 .
    drwxr-xr-x 17 root      root           4096 Mar 27 15:25 ..
    drwxrwxr-x  2 root      root          16384 Apr 15  2008 bin
    drwxrwxr-x  3 root      root           4096 May 28  2007 help
    drwxrwxr-x 35 root      root          12288 Aug 08  2008 include
    drwxrwxr-x  6 root      root          12288 Aug 08  2008 lib
    drwxrwxr-x  2 root      root           4096 May 28  2007 libexec
    drwxrwxr-x 13 root      root           4096 May 14  2008 local
    drwxrwxr-x  3 root      root           4096 May 28  2007 man
    drwxrwxr-x 16 root      root           4096 Sep 10  2008 photon
    drwxrwxr-x  6 root      root           4096 May 28  2007 qnx630
    drwxrwxr-x  2 root      root           4096 Oct 23  2007 sbin
    drwxrwxr-x 14 root      root           4096 May 28  2007 share

Retrieving system information for a QNX target:

    C:\qcl>perl qcl.pl --host=10.0.0.2 info
    ARCHITECTURE=x86
    CPU=x86
    ENDIAN=le
    HASVERSION=1
    HOSTNAME=localhost
    MACHINE=x86pc
    NUM_SRVCS=1
    OS=nto
    RELEASE=6.3.2
    SYSNAME=QNX
    TIMEZONE=EET-02EEST-03,M3.5.0/2,M10.5.0/2
    VERSION=2006/03/16-14:19:50EST

=head1 AUTHOR

Kaloyan Tenchov, L<http://kaloyan.tenchov.name/>

=head1 COPYRIGHT

Copyright (c) 2009 Kaloyan Tenchov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=cut
