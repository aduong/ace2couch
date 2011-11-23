#!/usr/bin/perl
# loadcouch.pl

# Jace -> Couch structured objects
# provide the jace as files or through STDIN

use strict;
use warnings;
use Getopt::Long;
use URI::Escape::XS qw(uri_escape);
use WormBase::JaceConverter qw(treematrix2hash);
use AD::Couch; # buffered couchloader, unfortunate namespace. WIP

use constant LOCALHOST => '127.0.0.1';

my ($host, $port, $db) = (LOCALHOST, 5984, 'test');
my $quiet;

GetOptions(
    'host=s'        => \$host,
    'port=s'        => \$port,
    'database|db=s' => \$db,
    'quiet'         => \$quiet,
);

unless ($quiet) {
    print "Will load to http://$host:$port/$db\n";
    print 'Is that okay? ';
    my $res = <STDIN>;
    exit unless $res =~ /^y/i;
}

my $couch = AD::Couch->new(
    host      => $host,
    port      => $port,
    database  => $db,
    blocksize => 50_000, # memory requirements
);

LOOP:
while () {
    my ($data, $data_size);
    {
        local $/ = "\n\n";
        $data = <>;
        last LOOP unless defined $data;
    }

    ## parse input into matrix
    open my $table, '<', \$data;

    my ($treewidth, $matrix) = (0, []);
    while (<$table>) {
        chomp;
        my @row = split /\t/;
        push @$matrix, \@row;
        $treewidth = @row if @row > $treewidth;
    }
    # free up memory
    undef $data; 
    undef $table;

    ## parse matix into hash structure
    my $hash = treematrix2hash($matrix, 0, 0, undef, $treewidth);
    unless ($hash) {
        warn 'Could not parse data into a hash structure';
        next;
    }

    ## rearrange the hash into Couch doc format (with _id)
    my $key = (keys %$hash)[0];
    $hash = $hash->{$key};
    $hash->{_id} = uri_escape($key);

    ## load into Couch
    $couch->add_doc($hash); # will flush periodically to couch
}
