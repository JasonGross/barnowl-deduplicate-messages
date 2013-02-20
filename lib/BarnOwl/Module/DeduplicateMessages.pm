use warnings;
use strict;

=head1 NAME

BarnOwl::Module::DeduplicateMessages

=head1 DESCRIPTION

Provides the ability to delete duplicate messages as they arrive.

=cut

package BarnOwl::Module::DeduplicateMessages;

our $VERSION = 0.1;

my $message_cache = {};

my $new_variable_enum;
if (defined &BarnOwl::new_variable_enum) { # XXX Doesn't exist in 1.8.  Remove when 1.9 becomes standard.
    $new_variable_enum = \&BarnOwl::new_variable_enum;
} else {
    $new_variable_enum = \&BarnOwl::new_variable_string;
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
        validsettings  => [qw(keep-first keep-first-and-last keep-last keep-all)],
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
    my ($class, $instance) = ($m->class, $m->instance);
    return if $format eq 'keep-all';
    return unless $m->is_zephyr;
    my $old_m = $message_cache->{$class}->{$instance};
    if (defined $old_m && are_messages_equal($m, $old_m)) {
        if ($format eq 'keep-first') {
            $m->delete_and_expunge;
        } elsif ($format eq 'keep-last') {
            $old_m->delete_and_expunge;
            $message_cache->{$class}->{$instance} = $m;
        } elsif ($format eq 'keep-first-and-last') {
            $old_m->delete_and_expunge unless $old_m->{"__deduplicate_messages_first"};
            $message_cache->{$class}->{$instance} = $m;
        } else {
            die "Invalid setting `$format' for variable duplicate-message-format.\n";
        }
        return;
    }
    $m->{"__deduplicate_messages_first"} = 1; # XXX Hack
    $message_cache->{$class}->{$instance} = $m;
}

my @fields = qw(type direction body sender recipient login private
                class instance realm opcode hostname auth);
# This is very hackish.  I don't like it.
sub are_messages_equal {
    my ($m1, $m2) = @_;
    foreach my $field (@fields) {
        my ($val1, $val2) = ($m1->{$field}, $m2->{$field});
        return 0 unless (defined $val1 == defined $val2) && ($val1 eq $val2);
    }
    return 1;
}

1;
