# NAME

qcl.pl - QNX QCONN service provider client.

# SYNOPSIS

qcl.pl \[_options_\] \[\[--\] _command_ \[_parameters_\]\]

# COMMANDS

- **info**

    Retrieves system information for the target the QCONN server is running on.
    This is the default command.

- **versions**

    Retrieves a list of services supported by the QCONN server and their versions.

- **exec** _command_ \[_parameters_\]

    Executes the specified command on the target the QCONN server is running on.
    The use of "--" in front of the command is encouraged to avoid parameter misinterpretation.

- **put** _source_ _target_

    Transfers the file specified as source to the target the QCONN server is running on.
    The --mode option may be used to specify permissions for the file when it is created.

- **get** _source_ _target_

    Transfers the file specified as source from the target the QCONN server is running on.

- **rm** _target_

    Deletes the specified file or directory on the target the QCONN server is running on.

- **mkdir** _target_

    Creates the specified directory on the target the QCONN server is running on.

- **chmod** _target_

    Changes the permissions of the specified file or directory on the target the QCONN server
    is running on. The permissions are specified with the --mode option.

- **kill** _pid_ _signal_

    Sends the specified signal to the process with the specified PID on the target the QCONN
    server is running on.

# OPTIONS

- **--host**=_address_

    Specifies QCONN server as hostname or IP address. Default is localhost.

- **--port**=_port_

    Specifies QCONN server TCP port. Default is 8000.

- **--mode**=_permissions_

    Specifies file permissions used with some commands. Default is 0666.

- **--version**

    Prints program version.

- **--help**

    Prints a brief help message.

- **--man**

    Prints detailed program documentation.

# DESCRIPTION

qcl.pl is a Perl script working as a QNX QCONN service provider client. It allows
controlling a QCONN server from the command-line and automating certain development
activities for the QNX platform without using additional server applicaitons (e.g.
Telnet, FTP, SSH, etc.).

This script is far from complete and is not intended to replace the use of the
QNX Momentics IDE.

The Net::Telnet Perl module is required ([http://search.cpan.org/~jrogers/Net-Telnet-3.03/lib/Net/Telnet.pm](http://search.cpan.org/~jrogers/Net-Telnet-3.03/lib/Net/Telnet.pm)).

# EXAMPLES

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

# AUTHOR

Kaloyan Tenchov, [http://github.com/zayfod/qcl](http://github.com/zayfod/qcl)

# COPYRIGHT

Copyright (c) 2009-2014 Kaloyan Tenchov

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
