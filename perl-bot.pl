#!/usr/bin/env perl
use strict;
use warnings;

use lib 'lib';
use WebService::Lingr::Bot;
use Furl;
use URI::Escape qw(uri_escape_utf8);
use JSON qw(decode_json);
use Encode qw(decode_utf8);
use Text::Shorten qw(shorten_scalar);
use Getopt::Long;
use AE;

my $host = '127.0.0.1';
my $port = 6000;
GetOptions(
    'host=s' => \$host,
    'port=s' => \$port,
) or die;

sub lleval {
    my $src = shift;
    my $ua = Furl->new(agent => 'lleval2lingr', timeout => 5);
    my $res = $ua->get('http://api.dan.co.jp/lleval.cgi?l=pl&s=' . uri_escape_utf8($src));
    $res->is_success or die $res->status_line;
    print $res->content, "\n";
    return decode_json($res->content);
}

my $bot = WebService::Lingr::Bot->new();
$bot->register(qr/^!\s*(.*)/ => sub {
    my ($cb, $event, $code) = @_;

    unless ($code =~ m{^(print|say)}) {
        $code = "print sub { ${code} }->()";
    }
    my $res = lleval($code);
    if (defined $res->{error}) {
        $cb->(shorten_scalar($res->{error}, 80));
    } else {
        $cb->(shorten_scalar($res->{stdout} . $res->{stderr}, 80));
    }
});
$bot->register(qr/^perldoc\s+(.*)/ => sub {
    my ($cb, $event, $arg) = @_;

    pipe(my $rh, my $wh);

    my $pid = fork();
    $pid // do {
        close $rh;
        close $wh;
        die $!;
    };

    if ($pid) {
        # parent
        close $wh;

        my $ret = '';
        my $sweep;
        my $timer = AE::timer(10, 0, sub {
            kill 9, $pid;
        });
        my $child; $child = AE::child($pid, sub {
            undef $timer;
            $ret =~ s/NAME\n//;
            $ret =~ s/\nDESCRIPTION\n/\n/;
            $ret = shorten_scalar(decode_utf8($ret), 120);
            if ($arg =~ /\A[\$\@\%]/) {
                $ret .= "\n\nhttp://perldoc.jp/perlvar";
            } elsif ($arg =~ /\A-[a-z]\s+(.+)/) {
                $ret .= "\n\nhttp://perldoc.jp/$1";
            } else {
                $ret .= "\n\nhttp://perldoc.jp/$arg";
            }
            $cb->($ret);
            undef $sweep;
            undef $child;
        });
        $sweep = AE::io($rh, 0, sub {
            $ret .= scalar(<$rh>);
        });
    } else {
        # child
        close $rh;

        open STDERR, '>&', $wh
          or die "failed to redirect STDERR to logfile";
        open STDOUT, '>&', $wh
          or die "failed to redirect STDOUT to logfile";

        eval {
            require Pod::PerldocJp;
            local @ARGV = split /\s+/, $arg;
            if (@ARGV == 1 && $ARGV[0] =~ /^[\$\@\%]/) {
                unshift @ARGV, '-v';
            }
            unshift @ARGV, '-J';
            Pod::PerldocJp->run();
        };
        warn $@ if $@;

        exit 0;
    }
});
my $server = $bot->run(host => $host, port => $port);
print "http://$host:$port/\n";
AE::cv->recv;

