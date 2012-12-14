package Monkey::Patch::Action::Handle;

use 5.010;
use strict;
use warnings;

use Scalar::Util qw(weaken);
use Sub::Delete;

# VERSION

my %stacks;

sub __find_previous {
    my ($stack, $code) = @_;
    state $empty = sub {};

    for my $i (1..$#$stack) {
        if ($stack->[$i][1] == $code) {
            return $stack->[$i-1][2] // $stack->[$i-1][1];
        }
    }
    $empty;
}

sub new {
    my ($class, %args) = @_;

    my $type = $args{-type};
    delete $args{-type};

    my $code = $args{code};

    my $name = "$args{package}::$args{subname}";
    my $stack;
    if (!$stacks{$name}) {
        $stacks{$name} = [];
        push @{$stacks{$name}}, [sub => \&$name] if defined(&$name);
    }
    $stack = $stacks{$name};

    my $self = bless \%args, $class;

    no strict 'refs';
    no warnings 'redefine';
    if ($type eq 'sub') {
        push @$stack, [$type => $code];
        *$name = $code;
    } elsif ($type eq 'delete') {
        $code = sub {};
        $args{code} = $code;
        push @$stack, [$type, $code];
        delete_sub $name;
    } elsif ($type eq 'wrap') {
        weaken($self);
        my $wrapper = sub {
            my $ctx = {
                package => $self->{package},
                subname => $self->{subname},
                extra   => $self->{extra},
                orig    => __find_previous($stack, $self->{code}),
            };
            unshift @_, $ctx;
            goto &{$self->{code}};
        };
        push @$stack, [$type => $code => $wrapper];
        no warnings; # shut up warning about prototype mismatch
        *$name = $wrapper;
    }

    $self;
}

sub DESTROY {
    my $self = shift;

    my $name  = "$self->{package}::$self->{subname}";
    my $stack = $stacks{$name};
    my $code  = $self->{code};

    for my $i (0..$#$stack) {
        if($stack->[$i][1] == $code) {
            if ($stack->[$i+1]) {
                # check conflict
                if ($stack->[$i+1][0] eq 'wrap' &&
                        ($i == 0 || $stack->[$i-1][0] eq 'delete')) {
                    my $p = $self->{patcher};
                    warn "Warning: unapplying patch to $name ".
                        "(applied in $p->[1]:$p->[2]) before a wrapping patch";
                }
            }

            no strict 'refs';
            if ($i == @$stack-1) {
                if ($i) {
                    no warnings 'redefine';
                    if ($stack->[$i-1][0] eq 'delete') {
                        delete_sub $name;
                    } else {
                        no warnings; # shut up warning about prototype mismatch
                        *$name = $stack->[$i-1][2] // $stack->[$i-1][1];
                    }
                } else {
                    delete_sub $name;
                }
            }
            splice @$stack, $i, 1;
            last;
        }
    }
}

1;

=for Pod::Coverage .*
