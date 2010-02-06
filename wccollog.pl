#!/usr/bin/perl -w
# -----------------------------------------------------------------------------
# Copyright (c) 2010 by rettub <rettub@gmx.net>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------------
# wccollog
#
# print colored weechat logfiles.
#
#
# Usage:
#     wccollog [-weechat-home-dir <dir>] [-mynick <nick>] -logfile <file> 
#
#     pipe to less:
#
#     wccollog [-weechat-home-dir <dir>] [-mynick <nick>] -logfile <file> |less -R
#
#     or e.g. with grep (for a date):
#
#     grep "^2010-01" logfile | wccollog -l - |less -R
#
#    -l, -logfile:          weechat logfile or '-' for stdin
#
#    -w, -weechat-home-dir: directory to look for weechat.conf needed for colors
#                           default is ~/.weechat
#
#    -m, -mynick :          will color your nick with color of 'chat_nick_self'
#                           and will show highlights
#
#  Support for logfiles with lines like: yyyy-mm-dd hh:mm:ss   nick/action   message
#  Lines with actions like '--' | '<--' | '--> are filtered'
# ----------------------------------------------------------------------------

use 5.006;

use IO::File;
use Getopt::Long qw(:config no_ignore_case);
use Term::ANSIColor;
use Data::Dumper;
use strict;
use warnings;

my $Version = "0.01";

sub version {
    $Version;
}


my %Config=();

sub check_config {
    my ($weechat_home_dir) = shift;

    my $config = $weechat_home_dir . "/weechat.conf";

    open( CONFIG, '<', $config ) or do {
        die("can't open $config: $!");
        return undef;
    };

    my ( $i, $is_conf ) = ( 0, 0 );
    while (<CONFIG>) {
        $i++;
        last if $i == 3;
        next if $i == 1;
        $is_conf = 2 if (/# weechat\.conf -- /);
    }

    close CONFIG;
    die "$config is not a weechat config file!" unless $is_conf;
}

my @nc = ();
my $nicklist_prefix1;
my $nicklist_prefix3;
my $color_nicks_number;
my $nick_action;
my $color_chat_nick_self;
sub read_weechat_config {
    my ($weechat_home_dir) = shift;

    my $config = $weechat_home_dir . "/weechat.conf";

    open( CONFIG, '<', $config ) or do {
        die("can't open $config: $!");
        return undef;
    };

    while (<CONFIG>) {
        if (/=/) {
            my ( $var, $value ) = /(.*?)\s+=\s+(.*)/;
            $Config{$var} = $value;
        }
    }

    close CONFIG;

}

my ($dt, $dd);
sub process_config {
    $color_nicks_number = $Config{'color_nicks_number'};

    for ( my $i = 1 ; $i <= $Config{color_nicks_number} ; $i++ ) {
        $nc[$i] = convert_colors( $Config{ 'chat_nick_color' . sprintf( "%02d", $i ) } );
    }
    $nicklist_prefix1 = sprintf( "%s", colored [ convert_colors( $Config{'nicklist_prefix1'} ) ], "@", );
    $nicklist_prefix3 = sprintf( "%s", colored [ convert_colors( $Config{'nicklist_prefix3'} ) ], "+", );
    $dd = sprintf( "%s", colored ['yellow'], '-', colored ['reset'] );
    $dt = sprintf( "%s", colored ['yellow'], ':', colored ['reset'] );
    $nick_action = sprintf( "%s", colored ['white'], "*", colored ['reset'] );
    $color_chat_nick_self = sprintf( "%s", colored [ convert_colors( $Config{'chat_nick_self'} ) ]);
}

sub convert_colors {
    my $c = shift;

    if ( $c eq 'default' ) {
        return 'white';	    # FIXME get terminal fg
    } elsif ( $c eq 'brown' ) {
        return 'Bold yellow';
    } else {
        $c =~ s/light/Bold /;
        return $c;
    }

    return $c;
}

sub irc_nick_find_color {

    #nick_name := $_[0];

    my $color = 0;
    foreach my $c ( split( //, $_[0] ) ) {
        $color += ord($c);
    }
    $color = ( $color % $color_nicks_number );

    return $nc[ $color + 1 ];
}

sub color_nick {
    my $a  = shift;
    my $np = '[\@+^]';
    my ($b) = ( $a =~ /^$np?(.*)/ );

    return sprintf( "%s", $nicklist_prefix1 . colored [ irc_nick_find_color($b) ], $b, colored ['reset'] ) if $a =~ /^\@/;
    return sprintf( "%s", $nicklist_prefix3 . colored [ irc_nick_find_color($b) ], $b, colored ['reset'] ) if $a =~ /^\+/;
    return sprintf( "%s", colored                     [ irc_nick_find_color($a) ], $a, colored ['reset'] );
}

sub color_highlight {
    return sprintf( "%s", colored[ convert_colors( $Config{'chat_highlight'} ) .' on_' . convert_colors( $Config{'chat_highlight_bg'} ) ]  , $_[0] , colored ['reset']);
}

sub process_file {
    my $my_nick = shift;
    my $file    = shift;

    my $if = new IO::File;
    if ( $file eq '-' ) {
        $if->fdopen( fileno(STDIN), "r" )
          or die "can't open $!";
    } else {
        $if->open("< $file")
          or die "can't open $!";
    }

    if ( defined $my_nick ) {
        while (<$if>) {
            last unless defined $_;

            # FIXME different logfile formats
            my ( $d, $t, $n, $m ) = /(\d+-\d+-\d+) (\d+:\d+:\d+)\s+(.*?)\s+(.*)/;

            $d =~ s/-/$dd/g;
            $t =~ s/:/$dt/g;

            # XXX make it optional
            next if $n =~ /--|<--|-->/;

            if ( $n =~ /$my_nick/ ) {
                print "$d $t ". $color_chat_nick_self . $n, colored ['reset'], "\t$m\n";
            } elsif ( $m =~ /$my_nick/ ) {
                if ( $n eq '*' and $m =~ /^$my_nick/ ) {
                    $m =~ s/(.*?)\s+//;
                    ($n) = $1;
                    $m =~ s/^\s+//;
                    print "$d $t \t". $nick_action . "\t". $color_chat_nick_self . $n, colored ['reset'], " $m\n";
                } elsif ( $n eq '*' ) {
                    $m =~ s/(.*?)\s+//;
                    ($n) = $1;
                    $m =~ s/^\s+//;
                    print "$d $t \t". $nick_action . color_highlight($n), "\t$m\n";
                } else {
                    print "$d $t ", color_highlight($n), "\t$m\n";
                }
            } else {
                if ( $n eq '*' ) {
                    $m =~ s/(.*?)\s+//;
                    ($n) = $1;
                    $m =~ s/^\s+//;
                    print "$d $t \t". $nick_action . "\t", color_nick($n), colored ['reset'], " $m\n";
                } else {
                    print "$d $t ", color_nick($n), "\t$m\n";
                }
            }
        }
    } else {
        while (<$if>) {
            last unless defined $_;
            my ( $d, $t, $n, $m ) = /(\d+-\d+-\d+) (\d+:\d+:\d+)\s+(.*?)\s+(.*)/;

            $d =~ s/-/$dd/g;
            $t =~ s/:/$dt/g;

            # XXX make it optional
            next if $n =~ /--|<--|-->/;

            if ( $n eq '*' ) {
                $m =~ s/(.*?)\s+//;
                ($n) = $1;
                $m =~ s/^\s+//;
                    print "$d $t \t". $nick_action . "\t", color_nick($n), colored ['reset'], " $m\n";
            } else {
                print "$d $t ", color_nick($n), "\t$m\n";
            }
        }
    }
}

my ($mynick, $logfile, $weechat_home_dir, $help );
my $usage = <<EOF;
wccollog Version: $Version

usage:
    print output to stdout:

      wccollog [-weechat-home-dir <dir>] [-mynick <nick>] -logfile <file> 

    pipe to less:

      wccollog [-weechat-home-dir <dir>] [-mynick <nick>] -logfile <file> |less -R

    or e.g. with grep (for a date, no highlights):

      grep "^2010-01" logfile | wccollog -l - |less -R

    -l, -logfile:          weechat logfile or '-' for stdin

    -w, -weechat-home-dir: directory to look for weechat.conf needed for colors
                           default is ~/.weechat

    -m, -mynick :          will color your nick with color of 'chat_nick_self'
                           and will show highlights

  Support for logfiles with lines like: yyyy-mm-dd hh:mm:ss   nick/action   message
  Lines with actions like '--' | '<--' | '--> are filtered'
EOF

unless (
    GetOptions(
	"logfile=s" => \$logfile,
	"help" => \$help,
	"mynick=s" => \$mynick,
	"weechatr-home-dir=s" => \$weechat_home_dir,
    )
  )
{
    print "$usage";
    exit 1;
}

if ( defined $help ) {
    print "$usage";
    exit 0;
}

if ( not defined $logfile ) {
    die("you must specify a logfile! (piped input is on todo)");
}

if ( $logfile and $logfile eq '-' ) {
    #$logfile = 'STDIN';
}


# if ( $logfile and not -f $logfile ) {
#     die("logfile $logfile must be a file!");
# }

if ( not defined $weechat_home_dir ) {
    $weechat_home_dir = "$ENV{HOME}/.weechat";
}

check_config($weechat_home_dir);
read_weechat_config($weechat_home_dir);
process_config();
process_file($mynick, $logfile)


# setlocal equalprg=perltidy\ -q\ -l=160
# vim: tw=160 ai ts=4 sts=4 et sw=4  foldmethod=marker :
