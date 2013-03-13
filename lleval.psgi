#!/usr/bin/env perl
use strict;
use warnings;

use Furl;
use URI::Escape qw(uri_escape_utf8);
use Plack::Request;
use JSON qw(decode_json);
use Encode qw(encode_utf8);

sub lleval {
    my $src = shift;
    my $ua = Furl->new(agent => 'lleval2lingr', timeout => 5);
    my $res = $ua->get('http://api.dan.co.jp/lleval.cgi?l=pl&s=' . uri_escape_utf8($src));
    $res->is_success or die $res->status_line;
    print $res->content, "\n";
    return decode_json($res->content);
}

sub handler {
    my $json = shift;
    my $ret = '';
    if ( $json && $json->{events} ) {
        for my $event ( @{ $json->{events} } ) {
            if ( $event->{message}->{text} =~ qr/^!perl\s(.*)/ ) {
                my $res = lleval($1);
                if (defined $res->{error}) {
                    $ret = $res->{error};
                } else {
                    $ret = $res->{stdout} . $res->{stderr};
                }
            }
        }
    }
    return [200, ['Content-Type' => 'text/plain'], [encode_utf8 $ret]];
}

no warnings 'void';
sub {
    my $req = Plack::Request->new(shift);

    if ($req->method eq 'POST') {
        my $json = decode_json($req->content);
        return handler($json);
    } else {
        # とくによばれない
        return [200, ['Content-Type' => 'text/plain'], ["I'm lleval2lingr bot"]];
    }
};
