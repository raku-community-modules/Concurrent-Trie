class Concurrent::Trie {
    my class AlreadyInserted is Exception { }

    my class Node {
        has %.children;
        has Bool $.is-entry;
    
        my \EMPTY = Node.new;
        
        method EMPTY { EMPTY }

        method lookup-char(Str $char) {
            %!children{$char}
        }

        method clone-with-chars(@chars) {
            if @chars {
                my $first = @chars[0];
                my @rest = @chars.tail(*-1);
                if %!children{$first}:exists {
                    self.clone: children => {
                        %!children,
                        $first => %!children{$first}.clone-with-chars(@rest)
                    }
                }
                else {
                    self.clone: children => {
                        %!children,
                        $first => EMPTY.clone-with-chars(@rest)
                    }
                }
            }
            elsif $!is-entry {
                die AlreadyInserted.new;
            }
            else {
                self.clone: :is-entry
            }
        }
    }

    has Node $!root = Node.EMPTY;
    has atomicint $.elems;

    method insert(Str:D $value --> Nil) {
        if $value {
            my @chars = $value.comb;
            cas $!root, { .clone-with-chars(@chars) }
            $!elems⚛++;
            CATCH {
                when AlreadyInserted {
                    # Not a problem, exception is just to escape from the
                    # update attempt and not bump $!elems.
                }
            }
        }
    }

    method contains(Str:D $value --> Bool) {
        my $current = $!root;
        for $value.comb {
            $current .= lookup-char($_);
            return False without $current;
        }
        return $current.is-entry;
    }

    method entries(Str:D $prefix = '' --> Seq) {
        my $start = $!root;
        gather {
            my $current = $start;
            for $prefix.comb {
                $current .= lookup-char($_);
                last without $current;
            }
            entry-walk($prefix, $current) with $current;
        }
    }

    sub entry-walk(Str $prefix, Node $current) {
        take $prefix if $current.is-entry;
        for $current.children.kv -> $char, $child {
            entry-walk("$prefix$char", $child);
        }
    }

    multi method Bool(Concurrent::Trie:D: --> Bool) {
        $!elems != 0
    }
}

=begin pod

=head1 NAME

Concurrent::Trie - A lock-free concurrent trie (Text Retrieval) data structure

=head1 SYNOPSIS

=begin code :lang<raku>

use Concurrent::Trie;

my $trie = Concurrent::Trie.new;
say $trie.contains('brie');  # False
say so $trie;                # False
say $trie.elems;             # 0

$trie.insert('brie');
say $trie.contains('brie');  # True
say so $trie;                # True
say $trie.elems;             # 1

$trie.insert('babybel');
$trie.insert('gorgonzola');
say $trie.elems;             # 3
say $trie.entries();         # (gorgonzola babybel brie)
say $trie.entries('b');      # (babybel brie)

=end code

=head1 DESCRIPTION

A trie stores strings as a tree, with each level in the tree
representing a character in the string (so the tree's maximum depth
is equal to the number of characters in the longest entry). A trie
is especially useful for prefix searches, where all entries with a
given prefix are required, since this is obtained simply by walking
the tree according to the prefix, and then visiting all nodes below
that point to find entries.

This is a lock-free trie. Checking if the trie contains a particular
string B<never> blocks. Iterating the entries never blocks either,
and will provide a snapshot of all the entries at the time the 
C<entries`>method was called. An insertion uses optimistic concurrency
control, building an updated tree and then trying to commit it. This
offers a global progress bound: if one thread fails to insert, it's
because another thread did a successful insert.

This data structure is well suited to auto-complete style features
in concurrent applications, where new entries and lookups may occur
when, for example, processing web requests in parallel.

=head1 Methods

=head2 insert(Str $value --> Nil)

Inserts the passed string value into the trie.

=head2 contains(Str $value --> Bool:D)

Checks if the passed string value is in the trie. Returns C<True> if
so, and C<False> otherwise.

=head2 entries($prefix = '' --> Seq:D)

Returns a lazy iterator of all entries in the trie with the specified
prefix.  If no prefix is passed, the default is the empty prefix,
meaning that a call like C<$trie.entries()> will iterate B<all> entries
in the trie. The order of the results is not defined.

The results will be a snapshot of what was in the trie at the point
C<entries> was called; additions after that point will not be in the
C<entries> list.

=head2 elems(--> Int:D)

Gets the number of entries in the trie. The data structure maintains
a count, making this O(1) (as opposed to C<$trie.entries.elems>, which
would be O(n)).

=head2 Bool(--> Bool:D)

Returns C<True> if the number of entries in the trie is non-zero, and
C<False> otherwise.

=head1 AUTHOR

Jonathan Worthington

=head1 COPYRIGHT AND LICENSE

Copyright 2018 - 2024 Jonathan Worthington

Copyright 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
