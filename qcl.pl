#!/usr/bin/perl

#
# qcl.pl
# $Date$
# $Revision$
#
# Kaloyan Tenchov, 2009
#
# TODO:
#   - Parse error messages of file service.
#   - Ability to set permissions of files when using the put command.
#

use warnings;
use strict;

use Getopt::Long qw(:config auto_version auto_help);
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

my $command = 'info';
my $get_buf_size = 2*1024;      # There are problems when reading files with buffer size bigger than 2kB
my $put_buf_size = 16*1024;
my $q;


sub get_basename
{
    $_[0] =~ /([^\/\\]+)$/o;
    return $1;
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

    $q->print('Quit');
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

    $q->print('Quit');
    return 0;
}


sub cmd_exec
{
    my @lines;

    if ($#ARGV < 0)
    {
        print("Command not specified.\n");
        $q->print('Quit');
        return 1;
    }

    # Check launcher service version
    $_ = get_service_version('launcher');
    if ($_ < 257)
    {
        print("Unsupported launcer service version.\n");
        $q->print('Quit');
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
        $q->print('Quit');
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
    return -1 if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):\"(.+)\"$/oi || $4 ne $spec);
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
    if ($_ < 257)
    {
        print("Unsupported file service version $_.\n");
        $q->print('Quit');
        return 3;
    }

    # Switch to file service
    $q->prompt('/<qconn-file>\s*$/o');
    my @lines = $q->cmd('service file');
    if ($#lines < 0 || $lines[0] !~ /^OK$/o)
    {
        print("Failed to switch to file service.\n");
        $q->print('Quit');
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
        $q->print('Quit');
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
        $q->print('Quit');
        return 1;
    }
    binmode($sf);

    # Create target file
    $cmd = sprintf("o:\"%s\":%x:%x", $target, O_CREAT|O_TRUNC|O_WRONLY, S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):\"(.+)\"$/oi || $4 ne $target)
    {
        print("Failed to create target file $target.\n");
        close($sf);
        $q->print('Quit');
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
            if ($line !~ /^o:([0-9a-f]+):([0-9a-f]+)/oi || hex($1) != $numread)
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
        $q->print('Quit');
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
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):\"(.+)\"$/oi || $4 ne $source)
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
        if ($line !~ /^o:([0-9a-f]+):[0-9a-f]+:[0-9a-f]+/oi)
        {
            print("Failed reading from source file.\n");
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

    # Close target file
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
        $q->print('Quit');
        return 1;
    }

    my $target = shift(@ARGV);

    # Switch to file service
    $_ = switch_to_file_service();
    return $_ if ($_ != 0);

    # Open source file
    $cmd = sprintf("o:\"%s\":%x", $source, O_RDONLY);
    @lines = $q->cmd($cmd);
    if ($#lines < 0 || $lines[0] !~ /^o:([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):\"(.+)\"$/oi || $4 ne $source)
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
        if ($line !~ /^o:([0-9a-f]+):[0-9a-f]+:[0-9a-f]+/oi)
        {
            print("Failed reading from source file.\n");
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

    # Close target file
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


$| = 1;

# Process command-line
GetOptions
(
    'help|?' => \$opt_help,
    'man' => \$opt_man,
    'host=s' => \$opt_host,
    'port=i' => \$opt_host
) or pod2usage(2);

pod2usage(1) if $opt_help;
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

# FIXME
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
    !$q->waitfor(Match => $q->prompt, String => "error linemode-or-echo-not-supported\n") ||
    !$q->waitfor(Match => $q->prompt, String => "error linemode-or-echo-not-supported\n"))
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
else
{
    print("Unknown command \"$command\".\n");
}

# Close connection to server
$q->close();

exit($res);


__END__

=head1 NAME

qcl.pl - QCONN client.

=head1 SYNOPSIS

qcl.pl [options] [[--] command [parameters]]

=head1 OPTIONS

=over 8

=item B<--version>

Prints program version.

=item B<--help>

Prints a brief help message.

=item B<--man>

Prints detailed program documentation.

=back

=head1 DESCRIPTION

Under development.

=cut
