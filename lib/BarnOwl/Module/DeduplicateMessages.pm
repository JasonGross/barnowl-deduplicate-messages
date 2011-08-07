use warnings;
use strict;

=head1 NAME

BarnOwl::Module::DeduplicateMessages

=head1 DESCRIPTION

Provides the ability to delete duplicate messages as they arrive.

=cut

package BarnOwl::Module::DeduplicateMessages;

our $VERSION = 0.1;

my %message_cache = ();

my $new_variable_enum;
if (defined &BarnOwl::new_variable_enum) { # XXX Doesn't exist in 1.8.  Remove when 1.9 becomes standard.
    $new_variable_enum = \&BarnOwl::new_variable_enum;
} else {
    $new_variable_enum = \&BarnOwl::new_variable_string;
}

=head2 duplicate-message-display

This BarnOwl variable controls how much time, in minutes, must elapse after a
particular message before a duplicate of that message can be displayed.

=cut

BarnOwl::new_variable_int('duplicate-message-delay',
    {
        default => 0,
        summary => 'Minimum duration, in seconds, between duplicate messages'
    });

=head2 clear_message_cache TIME

Clears the cache of messages, to deduplicate, of all messages which arrived
before C<TIME>.

=cut

sub clear_message_cache {
    my ($min_time) = @_;
    foreach my $time (keys %message_cache) {
        delete $message_cache{$time} if $time < $min_time;
    }
}

=head2 duplicate-message-format

This BarnOwl variable controls which messages to keep on deduplication.
You may set C<duplicate-message-format> to the following values:

=over 4

=item keep-first

Keep the first of a set of duplicate messages.

=item keep-first-and-last

Keep the first and last of a set of duplicate messages.

=item keep-last

Keep the last of a set of duplicate messages.

=item keep-all

Do not delete duplicate messages.  This is the default.

=back
 set the `duplicate-message-format' to any of the following values:

  * keep-first  Keep the first of a set of duplicate messages.
    * keep-last   Keep the last of a set of duplicate messages.
       * keep-all    Do not delete duplicate messages.  This is the default.

=cut

$new_variable_enum->('duplicate-message-format',
    {
        default        => 'keep-all',
        summary        => 'Which messages to keep on deduplication.',
        valid_settings => [qw(keep-first keep-first-and-last keep-last keep-all)],
        description    => "Controls the which messages to keep on deduplication:\n\n"
                        . " keep-first           Keep the first of a set of duplicate messages.\n"
                        . " keep-first-and-last  Keep the first and last of a set of duplicate messages.\n"
                        . " keep-last            Keep the last of a set of duplicate messages.\n"
                        . " keep-all             Do not delete duplicate messages."
    });


=head2 on_receive_message MESSAGE

Method to be called when a new message is recieved.

=cut

$BarnOwl::Hooks::receiveMessage->add("BarnOwl::Module::DeduplicateMessages::on_receive_message");

sub on_receive_message {
    my ($m) = @_;
    my $format = BarnOwl::getvar('duplicate-message-format');
    my $time = time;
    return if $format eq 'keep-all';
    $message_cache{$time} = [] unless defined $message_cache{$time};
    clear_message_cache(time - 60 * BarnOwl::getvar('duplicate-message-delay'));
    foreach my $message_list_ref (values %message_cache) {
        foreach my $old_m (@$message_list_ref) {
            next unless defined $old_m;
            if (are_messages_equal($m, $old_m)) {
                if ($format eq 'keep-first') {
                    $m->delete_and_expunge;
                    push @$message_cache{$time}, $old_m;
                } elsif ($format eq 'keep-last') {
                    $old_m->delete_and_expunge;
                    undef $old_m;
                    push @$message_cache{$time}, $m;
                } elsif ($format eq 'keep-fist-and-last') {
                    $old_m->delete_and_expunge unless $old_m->{"__deduplicate_messages_first"};
                    undef $old_m;
                    push @$message_cache{$time}, $m;
                } else {
                    die "Invalid setting `$format' for variable duplicate-message-format.\n";
                }
                return;
            }
        }
    }
    $m->{"__deduplicate_messages_first"} = 1; # XXX Hack
    push @$message_cache{$time}, $m;
}

my @methods = qw(type direction body sender recipient login is_private is_login
                 is_logout is_loginout is_incoming is_outgoing is_admin is_meta
                 is_generic is_zephyr is_aim is_jabber is_icq is_yahoo is_msn
                 is_loopback is_ping is_mail is_personal class instance realm
                 opcode header host hostname auth fields zsig zwriteline
                 login_host login_tty);
# This is very hackish.  I don't like it.
sub are_messages_equal {
    my ($m1, $m2) = @_;
    foreach my $method (@methods) {
        my ($meth1, $meth2) = (\&{"$m1->$method"}, \&{"$m2->$method"});
        next unless defined $meth1 && defined $meth2;
        my ($val1, $val2) = ($meth1->(), $meth2->());
        return 0 unless (defined $val1 == defined $val2) && ($val1 eq $val2);
    }
    return 1;
}

1;
